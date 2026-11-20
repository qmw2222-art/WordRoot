import Observation
import StoreKit
import SwiftUI

@MainActor
@Observable
final class SubscriptionService {
    enum Action: Equatable {
        case idle, loading, purchasing, restoring
    }

    static let productID = "local.wordroot.ios.monthly"
    private(set) var product: Product?
    private(set) var expiration: Date?
    private(set) var action = Action.idle
    private(set) var message: String?
    var hasAccess: Bool { expiration.map { $0 > .now } ?? false }

    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var expirationTask: Task<Void, Never>?

    func monitor() async {
        async let initial: Void = refresh()
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID else { continue }
            await refresh()
            await transaction.finish()
        }
        await initial
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        var latest: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil,
                  !transaction.isUpgraded,
                  let date = transaction.expirationDate,
                  date > .now else { continue }
            latest = max(latest ?? .distantPast, date)
        }
        guard generation == refreshGeneration else { return }
        expiration = latest
        scheduleExpiration()
    }

    func load() async {
        guard action == .idle else { return }
        action = .loading
        defer { action = .idle }
        message = nil
        do {
            product = try await Product.products(for: [Self.productID]).first
            if product == nil { message = "暂时无法获取月订阅商品。你可以稍后重试。" }
        } catch {
            message = "无法连接 App Store。请检查网络后重试。"
        }
    }

    func buy() async {
        guard action == .idle, let product else { return }
        action = .purchasing
        defer { action = .idle }
        message = nil
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await refresh()
                await transaction.finish()
                message = hasAccess ? "月订阅已生效。" : "已收到交易，暂时无法确认权益。"
            case .success(.unverified):
                message = "无法验证购买。请稍后恢复购买。"
            case .pending:
                message = "购买正在等待批准或付款。确认后会自动更新权益。"
            case .userCancelled:
                message = "购买已取消。"
            @unknown default:
                message = "暂时无法确认购买结果，请稍后恢复购买。"
            }
        } catch {
            message = "购买未完成。请稍后重试。"
        }
    }

    func restore() async {
        guard action == .idle else { return }
        action = .restoring
        defer { action = .idle }
        message = nil
        do {
            try await AppStore.sync()
            await refresh()
            message = hasAccess ? "已恢复订阅权益。" : "当前 Apple 账号没有有效订阅。"
        } catch {
            message = "恢复购买未完成。请稍后再试。"
        }
    }

    private func scheduleExpiration() {
        expirationTask?.cancel()
        guard let expiration else { return }
        expirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(max(0, expiration.timeIntervalSinceNow)))
                await self?.refresh()
            } catch is CancellationError {
                return
            } catch {
                await self?.refresh()
            }
        }
    }
}

struct SubscriptionView: View {
    @Environment(SubscriptionService.self) private var subscription
    @State private var showManagement = false

    var body: some View {
        Form {
            Section("词根地图月订阅") {
                if subscription.hasAccess {
                    Label("订阅有效", systemImage: "checkmark.circle")
                }
                Text("解锁完整课程、练习和音频。到期后仍可查看记录和复习已学内容。")
                if let product = subscription.product, !subscription.hasAccess {
                    Button("订阅 · \(product.displayPrice) / 月") {
                        Task { await subscription.buy() }
                    }
                    Text("订阅会自动续费。你可以在 Apple 订阅设置中取消续费。")
                        .foregroundStyle(.secondary)
                } else if !subscription.hasAccess {
                    Button("重新获取商品") { Task { await subscription.load() } }
                }
                if subscription.action != .idle { ProgressView() }
                if let message = subscription.message { Text(message) }
            }
            Section {
                Button("恢复购买") { Task { await subscription.restore() } }
                Button("管理订阅") { showManagement = true }
            }
        }
        .navigationTitle("订阅")
        .disabled(subscription.action != .idle)
        .manageSubscriptionsSheet(isPresented: $showManagement)
        .task { await subscription.load() }
    }
}

import Foundation
import Observation
import StoreKit

enum MembershipPlan: String, CaseIterable, Identifiable {
    case monthly, yearly, lifetime

    var id: String { "local.wordroot.ios." + rawValue }
    var type: Product.ProductType { self == .lifetime ? .nonConsumable : .autoRenewable }

    var title: String {
        switch self {
        case .monthly: "月订阅"
        case .yearly: "年订阅"
        case .lifetime: "永久买断"
        }
    }

    var chinaReferencePrice: String {
        switch self {
        case .monthly: "¥6"
        case .yearly: "¥26"
        case .lifetime: "¥48"
        }
    }

    var billing: String {
        switch self {
        case .monthly: "每月自动续费"
        case .yearly: "每年自动续费"
        case .lifetime: "一次付清"
        }
    }
}

@MainActor
@Observable
final class SubscriptionService {
    enum Action: Equatable { case idle, loading, purchasing, restoring }

    private(set) var products: [MembershipPlan: Product] = [:]
    private(set) var activePlan: MembershipPlan?
    private(set) var holdsSubscription = false
    private(set) var checkedEntitlements = false
    private(set) var needsPurchaseVerification = false
    private(set) var action = Action.idle
    private(set) var message: String?
    var hasAccess: Bool { activePlan != nil }

    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var expirationTask: Task<Void, Never>?

    func monitor() async {
        async let initial: Void = refresh()
        async let statuses: Void = observeSubscriptionChanges()
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result,
                  MembershipPlan.allCases.contains(where: { $0.id == transaction.productID }) else { continue }
            await refresh()
            await transaction.finish()
        }
        _ = await (initial, statuses)
    }

    private func observeSubscriptionChanges() async {
        for await status in Product.SubscriptionInfo.Status.updates {
            guard case .verified(let transaction) = status.transaction,
                  MembershipPlan.allCases.contains(where: { $0.id == transaction.productID }) else { continue }
            await refresh()
        }
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        var permanent = false
        var unverified = false
        var subscription: (plan: MembershipPlan, end: Date)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                // A product ID can help identify a failed check. It never grants access.
                if MembershipPlan.allCases.contains(where: { $0.id == result.unsafePayloadValue.productID }) { unverified = true }
                continue
            }
            guard transaction.revocationDate == nil, !transaction.isUpgraded,
                  let plan = MembershipPlan.allCases.first(where: { $0.id == transaction.productID }),
                  plan.type == transaction.productType else { continue }
            if plan == .lifetime {
                permanent = true
                continue
            }
            guard var end = transaction.expirationDate else { continue }
            let status = await transaction.subscriptionStatus
            if let status {
                guard case .verified(let latest) = status.transaction,
                      latest.originalID == transaction.originalID else { unverified = true; continue }
                switch status.state {
                case .subscribed: break
                case .inGracePeriod:
                    guard case .verified(let info) = status.renewalInfo,
                          let grace = info.gracePeriodExpirationDate else { continue }
                    end = grace
                default: continue
                }
            }
            guard end > .now else { continue }
            if end > (subscription?.end ?? .distantPast) { subscription = (plan, end) }
        }
        guard refreshGeneration == generation else { return }
        activePlan = permanent ? .lifetime : subscription?.plan
        holdsSubscription = subscription != nil
        needsPurchaseVerification = unverified && activePlan == nil
        checkedEntitlements = true
        expirationTask?.cancel()
        if let end = subscription?.end {
            expirationTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow))) }
                catch { return }
                await self?.refresh()
            }
        }
    }

    func load() async {
        guard action == .idle, products.count < MembershipPlan.allCases.count else { return }
        action = .loading
        defer { action = .idle }
        do {
            let offers = try await Product.products(for: MembershipPlan.allCases.map(\.id))
            products = MembershipPlan.allCases.reduce(into: [:]) { result, plan in
                result[plan] = offers.first { $0.id == plan.id && $0.type == plan.type }
            }
            if products.isEmpty { message = "App Store 暂时没有提供可购买的方案。" }
            else if products.count < MembershipPlan.allCases.count { message = "部分方案暂时无法购买，可以稍后重新获取。" }
            else { message = nil }
        } catch {
            message = "暂时连不上 App Store。请检查网络后重试。"
        }
    }

    func buy(_ plan: MembershipPlan) async {
        guard action == .idle, !needsPurchaseVerification, activePlan != .lifetime, activePlan != plan, let product = products[plan] else { return }
        action = .purchasing
        defer { action = .idle }
        message = nil
        do {
            let previousPlan = activePlan
            switch try await product.purchase() {
            case .success(.verified(let transaction)) where transaction.productID == plan.id:
                await refresh()
                await transaction.finish()
                if previousPlan != nil && plan != .lifetime && activePlan != plan {
                    message = "已提交订阅变更，生效日期以 Apple 确认为准。"
                } else {
                    message = hasAccess ? "完整课程已开通。" : "购买已收到，正在确认权益。"
                }
            case .success:
                message = "暂时无法验证这笔购买。你可以稍后恢复购买。"
            case .pending:
                message = "购买正在等待批准或付款，确认后会自动开通。"
            case .userCancelled:
                message = "已取消本次购买。"
            @unknown default:
                message = "暂时无法确认购买结果，请稍后恢复购买。"
            }
        } catch {
            message = "购买未完成，请稍后重试。"
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
            if hasAccess { message = "已恢复完整课程。" }
            else if needsPurchaseVerification { message = "这笔购买仍待 Apple 验证，请稍后再试。" }
            else { message = "这个 Apple 账户当前没有可恢复的购买。" }
        } catch {
            message = "恢复购买未完成，请稍后再试。"
        }
    }
}

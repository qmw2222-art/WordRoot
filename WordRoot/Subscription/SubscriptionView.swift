import StoreKit
import SwiftUI

struct MembershipGate<Content: View>: View {
    @Environment(SubscriptionService.self) private var subscription
    let free: Bool
    let context: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        if free || subscription.hasAccess {
            content()
        } else if subscription.checkedEntitlements {
            SubscriptionView(context: context)
        } else {
            ProgressView("正在确认已购课程")
        }
    }
}

struct SubscriptionView: View {
    @Environment(SubscriptionService.self) private var subscription
    @State private var showManagement = false
    var context: String?

    var body: some View {
        Form {
            Section {
                if let plan = subscription.activePlan {
                    Label(plan == .lifetime ? "已永久解锁" : "已开通" + plan.title, systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .accessibilityIdentifier("membership.active")
                    Text("全部 100 天的课程、词根地图和练习都可以使用。")
                } else {
                    if let context { Text(context).font(.headline) }
                    if subscription.needsPurchaseVerification {
                        Text("检测到一笔待验证的购买。请先点「恢复购买」确认权益。")
                    }
                    Text("前 10 天可以免费学，也可以随时回来重温。开通后，接着学第 11–100 天和对应词族。")
                    Text("已学词的到期听音卡会继续出现在课程首页。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if subscription.activePlan != .lifetime {
                Section("选择开通方式") {
                    ForEach(MembershipPlan.allCases) { plan in
                        if plan != subscription.activePlan {
                            let product = subscription.products[plan]
                            Button {
                                Task { await subscription.buy(plan) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(plan.title).font(.headline)
                                        Text(plan.billing).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(product?.displayPrice ?? plan.chinaReferencePrice).font(.headline.monospacedDigit())
                                        if product == nil { Text("大陆参考价").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                            .disabled(product == nil || subscription.needsPurchaseVerification || subscription.action != .idle)
                            .accessibilityIdentifier("membership.buy." + plan.rawValue)
                        }
                    }
                    if subscription.products.count < MembershipPlan.allCases.count {
                        Text("取得当前 App Store 的价格后即可购买。").font(.footnote).foregroundStyle(.secondary)
                        Button("重新获取商店价格") { Task { await subscription.load() } }
                            .disabled(subscription.action != .idle)
                    }
                    Text(subscription.holdsSubscription
                         ? "已有订阅时，买断后请在「管理订阅」中关闭原订阅的自动续费。"
                         : "月订阅和年订阅会自动续费，可在 Apple 订阅设置里取消。永久买断只付一次。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if subscription.holdsSubscription {
                Text("你还有一份有效订阅，可在「管理订阅」中关闭自动续费。")
            }
            Section {
                Button("恢复购买") { Task { await subscription.restore() } }
                    .disabled(subscription.action != .idle)
                    .accessibilityIdentifier("membership.restore")
                Button("管理订阅") { showManagement = true }
                if subscription.action != .idle { ProgressView() }
                if let message = subscription.message {
                    Text(message).font(.footnote).accessibilityIdentifier("membership.message")
                }
            }
        }
        .navigationTitle(subscription.hasAccess ? "课程与购买" : "开通完整课程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .manageSubscriptionsSheet(isPresented: $showManagement)
        .task { await subscription.load() }
    }
}

import StoreKitTest
import XCTest

extension XCTestCase {
    /// Set up a genuine local purchase for tests that exercise lessons after day ten.
    @MainActor
    func usePurchasedCourse() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "WordRoot", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: file)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        _ = try await session.buyProduct(identifier: "local.wordroot.ios.lifetime")
        addTeardownBlock { session.clearTransactions() }
    }
}

import HegemonCore
import StoreKit
import StoreKitTest
import SwiftUI
import XCTest
@testable import AncientHegemon

/// The Store against AncientHegemon.storekit: prices, buying, buying elsewhere, Ask to Buy,
/// refunds, and what the game's table looks like with and without the Hittites.
/// Set TEST_RUNNER_SHOTS=/some/folder when running `xcodebuild test` to save screenshots there.
@MainActor
final class StoreTests: XCTestCase {
    private var session: SKTestSession!
    private let hittites = Expansion.named("hittites")!
    private var store: Store { Store.shared }

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "AncientHegemon")
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
        store.start()
        await store.loadProducts()
        await store.refreshEntitlements()
        store.problem = nil
    }

    func testTheHittitesAreOnSale() {
        XCTAssertEqual(store.price(of: hittites), "$1.99")
        XCTAssertEqual(store.product(for: hittites)?.type, .nonConsumable)
        XCTAssertFalse(store.owns("hittites"))
    }

    func testEveryExpansionHasAnEmpireAndAProduct() throws {
        let map = try GameMap.bundled()
        for e in Expansion.all {
            XCTAssertFalse(map.civilizations.filter { $0.expansion == e.id }.isEmpty, e.id)
            XCTAssertNotNil(store.product(for: e), e.productID)
        }
        // And every expansion empire on the map is sold.
        for civ in map.civilizations { if let e = civ.expansion { XCTAssertNotNil(Expansion.named(e), civ.id) } }
    }

    func testBuyingSeatsTheHittites() async throws {
        let game = GameSession()
        game.setExpansions(store.owned)
        XCTAssertEqual(game.table, ["greece", "egypt", "italia", "mesopotamia"])
        await store.buy(hittites)
        XCTAssertNil(store.problem)
        XCTAssertTrue(store.owns("hittites"))
        game.setExpansions(store.owned)
        XCTAssertEqual(game.table, ["greece", "egypt", "italia", "mesopotamia", "hatti"])
        XCTAssertNotNil(game.state.civs["hatti"])
        // A random world is drawn for all five.
        game.chooseWorld(4821)
        XCTAssertEqual(game.engine.map.civilizations.count, 5)
        XCTAssertNotNil(game.state.civs["hatti"])
    }

    func testAPurchaseFromAnotherDeviceIsSeenAndARefundTakesItBack() async throws {
        try session.buyProduct(productIdentifier: hittites.productID)
        try await waitUntilOwned()
        XCTAssertTrue(store.owns("hittites"))
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.refundTransaction(identifier: transaction.identifier)
        // The refund reaches the device a moment later.
        for _ in 0..<50 where store.owns("hittites") {
            try await Task.sleep(for: .milliseconds(100))
            await store.refreshEntitlements()
        }
        XCTAssertFalse(store.owns("hittites"))
    }

    /// What Restore Purchases ends with: entitlements read afresh, whatever the cached answer.
    /// (`AppStore.sync()` itself always asks to sign in, so it's checked by hand, not here.)
    func testEntitlementsOutrankTheCache() async throws {
        UserDefaults.standard.removeObject(forKey: "ownedExpansions")
        try session.buyProduct(productIdentifier: hittites.productID)
        try await waitUntilOwned()
        XCTAssertTrue(store.owns("hittites"))
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "ownedExpansions"), ["hittites"])
    }

    func testAskToBuyWaitsForApproval() async throws {
        session.askToBuyEnabled = true
        await store.buy(hittites)
        XCTAssertFalse(store.owns("hittites"))
        XCTAssertTrue(store.problem?.contains("approval") ?? false)
        let pending = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        // The approval arrives through Transaction.updates.
        for _ in 0..<50 where !store.owns("hittites") { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(store.owns("hittites"))
    }

    /// Screens for the App Store review screenshot and for checking by eye: the title screen with
    /// the Hittites locked, the Store, and the title screen once they're bought.
    func testScreenshots() async throws {
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first)
        let root = try XCTUnwrap(window.rootViewController)
        try await Task.sleep(for: .seconds(3))
        save(window, "title-locked")
        let sheet = UIHostingController(rootView: StoreView(store: store, state: GameSession().state, map: try .bundled()))
        root.present(sheet, animated: false)
        try await Task.sleep(for: .seconds(2))
        save(window, "review-store")
        await store.buy(hittites)
        try await Task.sleep(for: .seconds(1))
        save(window, "store-owned")
        sheet.dismiss(animated: false)
        try await Task.sleep(for: .seconds(3))
        save(window, "title-unlocked")
    }

    /// A purchase made outside the app reaches it a moment later.
    private func waitUntilOwned() async throws {
        for _ in 0..<50 where !store.owns("hittites") {
            try await Task.sleep(for: .milliseconds(100))
            await store.refreshEntitlements()
        }
    }

    private func save(_ window: UIWindow, _ name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOTS"], let png = image.pngData() {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        }
    }
}

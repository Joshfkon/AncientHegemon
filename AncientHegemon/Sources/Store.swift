import HegemonCore
import StoreKit
import SwiftUI

/// A paid expansion: one non-consumable in-app purchase that adds empires to the table
/// (DESIGN.md, "Paid expansions"). The empires themselves are data in map.json, tagged with
/// the expansion's id; this is only what the Store needs to sell it.
struct Expansion: Identifiable, Hashable {
    /// The id map.json's civilizations carry in `expansion`.
    let id: String
    /// The App Store Connect product id.
    let productID: String
    let title: String
    let pitch: String
    /// What's in it, line by line.
    let features: [String]

    static let all: [Expansion] = [
        Expansion(
            id: "hittites",
            productID: "com.joshuakonstantinos.ancienthegemon.empire.hittites",
            title: "The Hittites",
            pitch: "The Great Kings of Hatti, rivals of Egypt at Kadesh, masters of the chariot and the first to work iron.",
            features: [
                "A fifth empire to play: Hatti, a monarchy on the Anatolian plateau, with the chariot general Muwatalli",
                "Its own court: Hittite kings in their tall caps, a throne room of carved stone and lions, its city and its council",
                "Joins every game you play as a rival, on the classic board and on random worlds",
            ]),
    ]

    static func named(_ id: String) -> Expansion? { all.first { $0.id == id } }
}

/// The App Store side of expansions, with StoreKit 2: products and prices, buying, restoring,
/// and which expansions this Apple ID owns. No server: the App Store's signed transactions are
/// checked on the device, and StoreKit keeps them for offline launches.
@MainActor @Observable
final class Store {
    static let shared = Store()

    /// Products by id, once the App Store has answered.
    private(set) var products: [String: Product] = [:]
    /// Expansion ids owned. Starts from the last known answer so the title screen doesn't
    /// flicker while StoreKit checks; StoreKit's answer replaces it.
    private(set) var owned: Set<String>
    private(set) var purchasing: String?
    private(set) var restoring = false
    /// The last thing that went wrong, for an alert.
    var problem: String?
    /// Called whenever `owned` changes.
    var onChange: ((Set<String>) -> Void)?

    private static let cacheKey = "ownedExpansions"
    private var updates: Task<Void, Never>?

    private init() {
        owned = Set(UserDefaults.standard.stringArray(forKey: Self.cacheKey) ?? [])
        #if DEBUG
        // Launch with -unlockExpansions YES to play every empire without buying (screenshots).
        if UserDefaults.standard.bool(forKey: "unlockExpansions") { owned = Set(Expansion.all.map(\.id)) }
        #endif
    }

    /// Starts listening for transactions (purchases on another device, Ask to Buy approvals,
    /// refunds) and loads products and entitlements. Call once at launch.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result { await transaction.finish() }
                await self.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        do {
            let found = try await Product.products(for: Expansion.all.map(\.productID))
            products = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        } catch {
            // Offline or the App Store is unreachable: prices show once it answers.
        }
    }

    /// Asks StoreKit what this Apple ID owns now (refunded or revoked purchases drop out).
    func refreshEntitlements() async {
        var now: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil,
                  let e = Expansion.all.first(where: { $0.productID == t.productID }) else { continue }
            now.insert(e.id)
        }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "unlockExpansions") { now = Set(Expansion.all.map(\.id)) }
        #endif
        set(now)
    }

    func owns(_ expansion: String) -> Bool { owned.contains(expansion) }

    func product(for e: Expansion) -> Product? { products[e.productID] }

    /// The price to show, once known.
    func price(of e: Expansion) -> String? { product(for: e)?.displayPrice }

    func buy(_ e: Expansion) async {
        guard purchasing == nil else { return }
        if product(for: e) == nil { await loadProducts() }
        guard let product = product(for: e) else {
            problem = "The App Store can't be reached right now. Try again in a moment."
            return
        }
        purchasing = e.id
        defer { purchasing = nil }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    problem = "The App Store couldn't confirm that purchase."
                    return
                }
                await transaction.finish()
                await refreshEntitlements()
                Feedback.outcome(true)
            case .pending:
                problem = "Your purchase is waiting for approval. The empire unlocks as soon as it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Restore purchases: syncs this Apple ID's transactions with the App Store (it may ask to
    /// sign in), then checks entitlements again.
    func restore() async {
        restoring = true
        defer { restoring = false }
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            return
        } catch {
            problem = error.localizedDescription
        }
        await refreshEntitlements()
        problem = owned.isEmpty ? "No purchases to restore for this Apple ID." : problem
    }

    private func set(_ now: Set<String>) {
        guard now != owned else { return }
        owned = now
        UserDefaults.standard.set(Array(now).sorted(), forKey: Self.cacheKey)
        onChange?(now)
    }
}

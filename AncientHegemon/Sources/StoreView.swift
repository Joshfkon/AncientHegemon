import HegemonCore
import StoreKit
import SwiftUI

/// The Store, from the title screen: each expansion with its ruler in person, what's in it, a
/// buy button with the App Store's price, and Restore Purchases.
struct StoreView: View {
    let store: Store
    let state: GameState
    /// The classic map, which lists every empire and the expansion it comes from.
    let map: GameMap
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The base game is complete and free: four empires, the classic board, random worlds, scenarios and every difficulty. Expansions add new empires to play, and they join your games as rivals.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(Expansion.all) { e in card(e) }
                    HStack {
                        Button {
                            Task { await store.restore() }
                        } label: {
                            Label(store.restoring ? "Restoring…" : "Restore Purchases", systemImage: "arrow.clockwise")
                                .font(.callout.bold())
                        }
                        .disabled(store.restoring)
                        .accessibilityIdentifier("restorePurchases")
                        Spacer()
                        Text("One-time purchases, yours on every device signed in with your Apple ID.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(Parchment())
            .navigationTitle("Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { if store.products.isEmpty { await store.loadProducts() } }
        .alert("Store", isPresented: Binding(get: { store.problem != nil }, set: { if !$0 { store.problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.problem ?? "")
        }
    }

    private func card(_ e: Expansion) -> some View {
        let civs = map.civilizations.filter { $0.expansion == e.id }
        let owned = store.owns(e.id)
        return HStack(alignment: .top, spacing: 16) {
            ForEach(civs) { civ in
                RulerFigure(civ: civ.id, state: state, mood: owned ? .pleased : .neutral)
                    .frame(height: 190)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Palette.color(civ.id, state).opacity(0.5), .black.opacity(0.6)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(civs) { civ in
                        CivBanner.emblem(civ.id).frame(width: 26, height: 26).foregroundStyle(Palette.color(civ.id, state))
                    }
                    Text(e.title).font(.system(size: 24, weight: .black, design: .serif))
                }
                Text(e.pitch).font(.callout)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(e.features, id: \.self) { f in
                        Label(f, systemImage: "checkmark.seal.fill").font(.caption)
                            .labelStyle(.titleAndIcon)
                    }
                }
                buyButton(e, owned: owned)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.background.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Bronze.gradient, lineWidth: 1.5))
    }

    @ViewBuilder private func buyButton(_ e: Expansion, owned: Bool) -> some View {
        if owned {
            Label("Owned: choose it on the title screen", systemImage: "checkmark.circle.fill")
                .font(.callout.bold()).foregroundStyle(.green)
                .accessibilityIdentifier("owned-\(e.id)")
        } else {
            Button {
                Task { await store.buy(e) }
            } label: {
                HStack(spacing: 8) {
                    if store.purchasing == e.id { ProgressView().tint(.black) }
                    Text(store.price(of: e).map { "Buy for \($0)" } ?? "Loading price…")
                }
                .font(.headline)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(Bronze.gradient, in: Capsule())
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(store.purchasing != nil || store.price(of: e) == nil)
            .accessibilityIdentifier("buy-\(e.id)")
        }
    }
}

/// Over a banner whose expansion isn't owned: a lock, the price, and a tap to the Store.
struct LockedBannerCover: View {
    let expansion: Expansion?
    let store: Store

    var body: some View {
        ZStack {
            BannerShape().fill(.black.opacity(0.62))
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "lock.fill").font(.title3)
                Text(expansion.flatMap { store.price(of: $0) } ?? "Expansion")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Bronze.gradient, in: Capsule())
                    .foregroundStyle(.black)
                Text("Tap for the Store").font(.caption2).foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 30)
            }
            .foregroundStyle(.white)
        }
        .allowsHitTesting(false)
    }
}

/// The double-headed eagle of the Hittite kings (Alaca Höyük, Yazılıkaya): wings spread, a
/// head turned each way.
struct HittiteEagle: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        // Wings, stepped like carved feathers.
        for side: CGFloat in [-1, 1] {
            let x = { (d: CGFloat) in 0.5 + side * d }
            path.move(to: p(x(0.08), 0.38))
            path.addLine(to: p(x(0.48), 0.18))
            path.addLine(to: p(x(0.44), 0.34))
            path.addLine(to: p(x(0.5), 0.36))
            path.addLine(to: p(x(0.42), 0.5))
            path.addLine(to: p(x(0.46), 0.54))
            path.addLine(to: p(x(0.34), 0.64))
            path.addLine(to: p(x(0.12), 0.62))
            path.closeSubpath()
            // A neck and head, beak outward.
            path.move(to: p(x(0.04), 0.38))
            path.addLine(to: p(x(0.1), 0.16))
            path.addLine(to: p(x(0.16), 0.08))
            path.addLine(to: p(x(0.26), 0.12))
            path.addLine(to: p(x(0.18), 0.17))
            path.addLine(to: p(x(0.14), 0.38))
            path.closeSubpath()
        }
        // Body and fanned tail.
        path.addEllipse(in: CGRect(x: r.minX + 0.36 * r.width, y: r.minY + 0.3 * r.height, width: 0.28 * r.width, height: 0.38 * r.height))
        path.move(to: p(0.42, 0.64))
        path.addLine(to: p(0.34, 0.92))
        path.addLine(to: p(0.66, 0.92))
        path.addLine(to: p(0.58, 0.64))
        path.closeSubpath()
        return path
    }
}

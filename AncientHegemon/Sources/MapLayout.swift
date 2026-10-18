import CoreGraphics
import HegemonCore
import SwiftUI

/// Placeholder map geometry: rough longitude/latitude for each territory and sea, until the
/// painted board is photographed and territory outlines are traced over it.
enum MapLayout {
    static let territories: [TerritoryID: (lon: Double, lat: Double)] = [
        "hibernia": (-8, 53), "caledonia": (-4, 57), "britain": (-1.5, 52), "sitones": (14, 59),
        "saxone": (9, 53), "suebi": (13, 50), "venedi": (22, 53), "gaul": (2, 47),
        "hispania": (-5, 41), "pyrenees": (0.5, 43), "baetica": (-5, 37.5), "alps": (9, 46.3),
        "italia": (13.5, 42), "sardinia": (9, 40), "sicilia": (14, 37.3), "macedonia": (22, 41.3),
        "greece": (22.5, 38.3), "crete": (25, 35.2), "dacia": (25, 45.5), "thrace": (27, 42),
        "scythe": (33, 47.5), "sarmatia": (42, 48), "caucasus": (44, 43.5), "daha": (55, 41),
        "armenia": (42, 40), "media": (49, 36), "persia": (53, 31), "taurus": (35, 37.5),
        "anatolia": (31, 39.5), "cyprus": (33, 35), "syria": (37.5, 34.5), "mesopotamia": (44, 33),
        "petraea": (35, 30.5), "egypt": (31, 27), "arabia": (45, 25), "libya": (25, 30),
        "cyrenaica": (20, 31.5), "sahara": (8, 28), "numidia": (8, 35.5), "mauretania": (-5, 33),
    ]

    static let seas: [SeaZoneID: (lon: Double, lat: Double)] = [
        "atlantic": (-12, 46), "north_sea": (4, 57), "baltic": (18, 56.5), "western_med": (3, 39),
        "tyrrhenian": (11, 39.5), "ionian": (18, 36.5), "aegean": (25.5, 38.5), "eastern_med": (29, 33.5),
        "black_sea": (34, 43.5), "caspian": (50.5, 41.5), "red_sea": (38, 24.5), "persian_gulf": (51, 27),
    ]

    static let lonRange = (-14.0, 57.0)
    static let latRange = (23.0, 61.0)
    static let aspectRatio = (lonRange.1 - lonRange.0) / (latRange.1 - latRange.0) * 0.8

    static func point(lon: Double, lat: Double, in size: CGSize) -> CGPoint {
        CGPoint(x: (lon - lonRange.0) / (lonRange.1 - lonRange.0) * size.width,
                y: (latRange.1 - lat) / (latRange.1 - latRange.0) * size.height)
    }

    static func point(_ t: TerritoryID, in size: CGSize) -> CGPoint {
        let p = territories[t] ?? (0, 0)
        return point(lon: p.lon, lat: p.lat, in: size)
    }

    static func seaPoint(_ s: SeaZoneID, in size: CGSize) -> CGPoint {
        let p = seas[s] ?? (0, 0)
        return point(lon: p.lon, lat: p.lat, in: size)
    }
}

/// Colors for civilizations. Rebel factions take a lighter shade of the realm they split from.
enum Palette {
    static let base: [CivilizationID: Color] = [
        "greece": Color(red: 0.20, green: 0.42, blue: 0.85),
        "egypt": Color(red: 0.85, green: 0.65, blue: 0.13),
        "italia": Color(red: 0.80, green: 0.20, blue: 0.20),
        "mesopotamia": Color(red: 0.18, green: 0.62, blue: 0.35),
    ]

    static func color(_ civ: CivilizationID?, _ state: GameState) -> Color {
        guard let civ else { return Color(white: 0.92) }
        if civ == nativesID { return Color(white: 0.72) }
        if civ == barbariansID { return Color(red: 0.45, green: 0.30, blue: 0.20) }
        if let parent = state.civs[civ]?.rebelledFrom {
            return color(parent, state).opacity(0.45)
        }
        return base[civ] ?? .purple
    }

    static func name(_ civ: CivilizationID, _ state: GameState) -> String {
        if let display = state.civs[civ]?.displayName { return display }
        if civ == nativesID { return "Natives" }
        if civ == barbariansID { return "Barbarians" }
        return civ.prefix(1).uppercased() + civ.dropFirst()
    }
}

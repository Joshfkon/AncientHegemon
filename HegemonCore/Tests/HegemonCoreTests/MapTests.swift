import Foundation
import Testing
@testable import HegemonCore

@Suite struct MapTests {
    let map = try! GameMap.bundled()

    @Test func loadsFullMap() {
        #expect(map.territories.count == 40)
        #expect(map.seas.count == 12)
        #expect(map.chokepoints.count == 7)
        #expect(map.civilizations.count == 4)
    }

    @Test func everyTerritoryProducesGrain() {
        for t in map.territories {
            #expect(t.grain >= 1, "\(t.id)")
        }
    }

    @Test func landAdjacencyIsSymmetric() {
        for t in map.territories {
            for n in map.landNeighbors(of: t.id) {
                #expect(map.landNeighbors(of: n).contains(t.id), "\(t.id) -> \(n)")
                #expect(map.crossing(between: t.id, and: n) == map.crossing(between: n, and: t.id))
            }
        }
    }

    @Test func seaAdjacencyIsSymmetric() {
        for s in map.seas {
            for n in map.seaNeighbors(of: s.id) {
                #expect(map.seaNeighbors(of: n).contains(s.id), "\(s.id) -> \(n)")
            }
        }
    }

    @Test func coastsMatchTerritorySeas() {
        for s in map.seas {
            for t in map.coastalTerritories(of: s.id) {
                #expect(map.seas(bordering: t).contains(s.id))
            }
        }
    }

    @Test func crossingsAreRecorded() {
        #expect(map.areLandAdjacent("saxone", "gaul"))
        #expect(map.crossing(between: "saxone", and: "gaul") == .river)
        #expect(map.crossing(between: "gaul", and: "saxone") == .river)
    }

    @Test func islandsHaveNoLandNeighbors() {
        #expect(Set(map.islands) == ["crete", "cyprus", "hibernia", "sardinia", "sitones"])
        for id in map.islands {
            #expect(map.territory(id)!.isCoastal, "\(id) is unreachable")
        }
    }

    @Test func seaChokepointsGateLinks() {
        #expect(map.chokepoint(gating: "aegean", "black_sea")?.id == "bosporus")
        #expect(map.chokepoint(gating: "black_sea", "aegean")?.id == "bosporus")
        #expect(map.chokepoint(gating: "aegean", "eastern_med") == nil)
    }

    @Test func capitalsExist() {
        for civ in map.civilizations {
            #expect(map.territory(civ.capital) != nil)
        }
    }

    @Test func rejectsUnknownReference() {
        let json = """
        {"version":1,"territories":[{"id":"a","name":"A","terrain":"plains","grain":1,"resources":{},"seas":[]}],
         "landLinks":[["a","b"]],"seas":[],"seaLinks":[],"chokepoints":[],"civilizations":[]}
        """
        #expect(throws: MapError.unknownTerritory("b", context: "landLinks")) {
            try GameMap(json: Data(json.utf8))
        }
    }
}

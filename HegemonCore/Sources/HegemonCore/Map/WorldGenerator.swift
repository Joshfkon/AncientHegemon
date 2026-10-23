/// Random worlds: a new map for every game, made from a seed (DESIGN.md, "Random worlds").
///
/// The board is a grid of small hexagonal cells. Noise shaped by one of a few world plans (an
/// inland sea, two continents, a northern and a southern shore, scattered lands) decides land and
/// water; land cells are grown into territories and water cells into sea zones; rivers run down
/// to the coast along cell edges; terrain, grain and resources follow height, latitude and
/// rainfall. The four empires start on coasts far apart, each on its classic capital (same
/// terrain, grain and goods), and the rest of the land is named and given to kingdoms and tribes.
///
/// Everything is drawn from a SplitMix64 stream seeded by the world seed, so a seed always
/// makes the same world. Never iterate a Dictionary or Set to make a choice here.
public enum WorldGenerator {
    /// Bumped whenever the same seed would make a different world.
    public static let version = 1
    /// The map version of generated worlds (the classic map's is a small number).
    public static var mapVersion: Int { 100 + version }

    /// The world for a seed. `template` supplies the empires and their capitals (the classic map).
    public static func generate(seed: UInt64, template: GameMap) throws -> GameMap {
        var failure: Error = MapError.invalid("no world could be made")
        // A plan that doesn't work out (no fair starts, too few lands) is redrawn from the same
        // seed's next attempt, so the result is still fixed by the seed.
        for attempt in 0..<40 {
            do {
                var builder = WorldBuilder(seed: seed, attempt: attempt, template: template)
                return try builder.build()
            } catch {
                failure = error
            }
        }
        throw failure
    }
}

private struct Retry: Error {
    let reason: String
}

/// A binary min-heap of (cost, node), ties broken by node, for Dijkstra growth.
private struct Heap {
    private var items: [(Double, Int)] = []
    var isEmpty: Bool { items.isEmpty }

    private func less(_ a: (Double, Int), _ b: (Double, Int)) -> Bool {
        a.0 < b.0 || (a.0 == b.0 && a.1 < b.1)
    }

    mutating func push(_ cost: Double, _ node: Int) {
        items.append((cost, node))
        var i = items.count - 1
        while i > 0 {
            let p = (i - 1) / 2
            guard less(items[i], items[p]) else { break }
            items.swapAt(i, p)
            i = p
        }
    }

    mutating func pop() -> (Double, Int) {
        let top = items[0]
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, less(items[l], items[m]) { m = l }
                if r < items.count, less(items[r], items[m]) { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
        }
        return top
    }
}

private struct WorldBuilder {
    // Flat-topped hexes in "units": a cell's centre is (3c, 2r + c % 2); its corners are at
    // (±2, 0) and (±1, ±1) from it. One unit is half a side across and half a cell's height down.
    static let cols = 64, rows = 28
    static let side = 19.0
    static let ux = side / 2
    static let uy = side * 0.8660254037844386
    static let minX = 100.0, minY = 5.0, maxX = 1905.0, maxY = 920.0
    /// Neighbour offsets in units, and corner offsets: edge d runs from corner d to corner d+1
    /// and faces neighbour d.
    static let nOff = [(3, 1), (0, 2), (-3, 1), (-3, -1), (0, -2), (3, -1)]
    static let vOff = [(2, 0), (1, 1), (-1, 1), (-2, 0), (-1, -1), (1, -1)]

    let seed: UInt64
    let template: GameMap
    var rng: SeededRNG
    let n = cols * rows
    var neighbors: [[Int?]] = []

    var elev: [Double] = []
    var isLand: [Bool] = []
    var threshold = 0.0
    var topElev = 1.0
    /// Each land cell's territory (region index), -1 for water.
    var owner: [Int] = []
    /// Each water cell's sea, -1 for land.
    var seaOf: [Int] = []
    var regionCount = 0
    var seaCount = 0
    var plan = 0

    init(seed: UInt64, attempt: Int, template: GameMap) {
        self.seed = seed
        self.template = template
        rng = SeededRNG(seed: seed &* 0x2545_F491_4F6C_DD1D ^ UInt64(attempt) &* 0x9E37_79B9_7F4A_7C15 ^ 0xA5E5_0C1E)
        for i in 0..<n {
            let (vx, vy) = Self.units(i)
            neighbors.append(Self.nOff.map { Self.cell(vx + $0.0, vy + $0.1) })
        }
    }

    // MARK: Geometry

    static func units(_ i: Int) -> (Int, Int) {
        let c = i % cols, r = i / cols
        return (3 * c, 2 * r + (c & 1))
    }

    static func cell(_ vx: Int, _ vy: Int) -> Int? {
        guard vx >= 0, vx % 3 == 0 else { return nil }
        let c = vx / 3
        guard c < cols else { return nil }
        let rr = vy - (c & 1)
        guard rr >= 0, rr % 2 == 0 else { return nil }
        let r = rr / 2
        guard r < rows else { return nil }
        return r * cols + c
    }

    static func point(_ vx: Int, _ vy: Int) -> (Double, Double) {
        (minX + Double(vx) * ux, minY + Double(vy) * uy)
    }

    static func center(_ i: Int) -> (Double, Double) {
        let (vx, vy) = units(i)
        return point(vx, vy)
    }

    static func vertexKey(_ vx: Int, _ vy: Int) -> Int { (vx + 4) * 256 + (vy + 4) }
    static func vertexUnits(_ key: Int) -> (Int, Int) { (key / 256 - 4, key % 256 - 4) }

    func vertex(_ i: Int, _ d: Int) -> Int {
        let (vx, vy) = Self.units(i)
        return Self.vertexKey(vx + Self.vOff[d].0, vy + Self.vOff[d].1)
    }

    func landNeighbors(_ i: Int) -> [Int] { neighbors[i].compactMap { $0 }.filter { isLand[$0] } }

    // MARK: Randomness

    mutating func unit() -> Double { Double(rng.next() >> 11) / Double(1 << 53) }
    mutating func int(_ bound: Int) -> Int { bound <= 1 ? 0 : Int(rng.next() % UInt64(bound)) }

    func hash(_ x: Int, _ y: Int, _ salt: UInt64) -> Double {
        var z = seed ^ salt &* 0xD6E8_FEB8_6659_FD93
        z ^= UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        z ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    func valueNoise(_ x: Double, _ y: Double, _ salt: UInt64) -> Double {
        let x0 = x.rounded(.down), y0 = y.rounded(.down)
        let fx = x - x0, fy = y - y0
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let ix = Int(x0), iy = Int(y0)
        let a = hash(ix, iy, salt), b = hash(ix + 1, iy, salt)
        let c = hash(ix, iy + 1, salt), d = hash(ix + 1, iy + 1, salt)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    func fbm(_ x: Double, _ y: Double, _ salt: UInt64) -> Double {
        var total = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for o in 0..<4 {
            total += amp * valueNoise(x * freq, y * freq, salt &+ UInt64(o) &* 101)
            norm += amp
            amp *= 0.5
            freq *= 2
        }
        return total / norm
    }

    // MARK: Build

    mutating func build() throws -> GameMap {
        shapeLand()
        growTerritories()
        growSeas()
        return try finish()
    }

    /// Height from noise and the world's plan; the highest share of cells is land.
    mutating func shapeLand() {
        plan = int(4)
        let landShare: Double
        // The plan's pull: positive where land should be.
        var bias: (Double, Double) -> Double
        switch plan {
        case 0:
            // An inland sea, as the Mediterranean: shores all round, water in the middle.
            let cx = 0.5 + (unit() - 0.5) * 0.16, cy = 0.5 + (unit() - 0.5) * 0.14
            let rx = 0.3 + unit() * 0.08, ry = 0.26 + unit() * 0.08
            bias = { x, y in
                let dx = (x - cx) / rx, dy = (y - cy) / ry
                return min(1.3, (dx * dx + dy * dy).squareRoot()) * 0.6
            }
            landShare = 0.5
        case 1:
            // Two continents across a sea, as Europe and Asia across the Aegean.
            let ax = 0.24 + unit() * 0.08, ay = 0.35 + unit() * 0.3
            let bx = 0.76 - unit() * 0.08, by = 0.35 + unit() * 0.3
            let ra = 0.3 + unit() * 0.06, rb = 0.3 + unit() * 0.06
            bias = { x, y in
                let da = (((x - ax) * 1.9) * ((x - ax) * 1.9) + (y - ay) * (y - ay)).squareRoot() / ra
                let db = (((x - bx) * 1.9) * ((x - bx) * 1.9) + (y - by) * (y - by)).squareRoot() / rb
                return max(1 - da, 1 - db) * 1.1
            }
            landShare = 0.42
        case 2:
            // A northern and a southern shore with a long sea between, as Europe and Africa.
            let mid = 0.46 + unit() * 0.1
            let wave = 0.06 + unit() * 0.06, phase = unit() * 6.283
            let slope = (unit() - 0.5) * 0.2
            bias = { x, y in
                let t = (x * 2.2 + phase) - ((x * 2.2 + phase) / 6.283).rounded(.down) * 6.283
                // A smooth wave without sin: a parabola per half period.
                let u = t / 3.1415 - 1, s = 1 - u * u * 2
                let centre = mid + slope * (x - 0.5) + wave * s
                return abs(y - centre) * 2.3 - 0.25
            }
            landShare = 0.48
        default:
            // Scattered lands: big islands and peninsulas, where fleets rule.
            bias = { x, y in
                let dx = (x - 0.5) * 1.5, dy = y - 0.5
                return 0.45 - (dx * dx + dy * dy).squareRoot() * 0.7
            }
            landShare = 0.4
        }
        // The plan sets the broad shape; the noise its capes, bays and islands.
        let noiseWeight = plan == 3 ? 2.0 : 1.6
        let salt = UInt64(int(1 << 30))
        elev = (0..<n).map { i in
            let (x, y) = Self.center(i)
            let nx = (x - Self.minX) / (Self.maxX - Self.minX), ny = (y - Self.minY) / (Self.maxY - Self.minY)
            return 0.5 * bias(nx, ny) + noiseWeight * (fbm(x / 210, y / 210, salt) - 0.5)
        }
        let order = (0..<n).sorted { elev[$0] > elev[$1] || (elev[$0] == elev[$1] && $0 < $1) }
        let landCount = Int(Double(n) * landShare)
        isLand = [Bool](repeating: false, count: n)
        for i in order.prefix(landCount) { isLand[i] = true }
        threshold = elev[order[landCount - 1]]
        topElev = elev[order[0]]
        for _ in 0..<2 {
            // Specks of land sink; ponds are filled.
            for comp in components(where: { isLand[$0] }) where comp.count < 5 {
                for i in comp { isLand[i] = false }
            }
            for comp in components(where: { !isLand[$0] }) where comp.count < 60 {
                if !comp.contains(where: { neighbors[$0].contains(nil) }) {
                    for i in comp { isLand[i] = true }
                }
            }
        }
    }

    /// Connected groups of cells matching `test`, each in BFS order, ordered by first cell.
    func components(where test: (Int) -> Bool) -> [[Int]] {
        var seen = [Bool](repeating: false, count: n)
        var result: [[Int]] = []
        for start in 0..<n where test(start) && !seen[start] {
            var comp = [start]
            seen[start] = true
            var k = 0
            while k < comp.count {
                for m in neighbors[comp[k]].compactMap({ $0 }) where test(m) && !seen[m] {
                    seen[m] = true
                    comp.append(m)
                }
                k += 1
            }
            result.append(comp)
        }
        return result
    }

    /// `k` well-spread cells of a group, chosen far from one another (with a little chance).
    mutating func spreadSeeds(_ cells: [Int], _ k: Int, passable: (Int) -> Bool) -> [Int] {
        var dist = [Int](repeating: Int.max, count: n)
        var seeds: [Int] = []
        var next = cells[int(cells.count)]
        for _ in 0..<k {
            seeds.append(next)
            var queue = [next]
            dist[next] = 0
            var q = 0
            while q < queue.count {
                let c = queue[q]
                q += 1
                for m in neighbors[c].compactMap({ $0 }) where passable(m) && dist[m] > dist[c] + 1 {
                    dist[m] = dist[c] + 1
                    queue.append(m)
                }
            }
            var best = -1.0
            for c in cells {
                let score = Double(dist[c] == Int.max ? 999 : dist[c]) + unit() * 1.5
                if score > best { best = score; next = c }
            }
        }
        return seeds
    }

    /// Dijkstra growth from seeds over passable cells; returns each cell's seed index (or -1).
    func grow(_ seeds: [Int], passable: (Int) -> Bool, cost: (Int, Int) -> Double) -> [Int] {
        var label = [Int](repeating: -1, count: n)
        var best = [Double](repeating: .infinity, count: n)
        var heap = Heap()
        for (k, s) in seeds.enumerated() {
            best[s] = 0
            label[s] = k
            heap.push(0, s)
        }
        var done = [Bool](repeating: false, count: n)
        while !heap.isEmpty {
            let (d, c) = heap.pop()
            if done[c] { continue }
            done[c] = true
            for m in neighbors[c].compactMap({ $0 }) where passable(m) && !done[m] {
                let nd = d + cost(c, m)
                if nd < best[m] {
                    best[m] = nd
                    label[m] = label[c]
                    heap.push(nd, m)
                }
            }
        }
        return label
    }

    /// Land into territories of about 19 cells; tiny ones join a neighbour; holes are filled.
    mutating func growTerritories() {
        let landCells = (0..<n).filter { isLand[$0] }.count
        let target = min(46, max(34, Int((Double(landCells) / 19).rounded())))
        let average = Double(landCells) / Double(target)
        var seeds: [Int] = []
        for comp in components(where: { isLand[$0] }) {
            let k = comp.count < 14 ? 1 : max(1, Int((Double(comp.count) / average).rounded()))
            let land = isLand
            seeds += spreadSeeds(comp, k, passable: { land[$0] })
        }
        let roughness = (0..<n).map { _ in unit() * 1.2 }
        let land = isLand, height = elev
        owner = grow(seeds, passable: { land[$0] },
                     cost: { a, b in 1 + roughness[b] + 4 * abs(height[a] - height[b]) })
        regionCount = seeds.count

        // Small lands join their smallest neighbour (islands keep theirs).
        while true {
            var size = [Int](repeating: 0, count: regionCount)
            for i in 0..<n where owner[i] >= 0 { size[owner[i]] += 1 }
            var merged = false
            for r in (0..<regionCount).sorted(by: { size[$0] < size[$1] || (size[$0] == size[$1] && $0 < $1) })
            where size[r] > 0 && size[r] < 8 {
                var around: [Int] = []
                for i in 0..<n where owner[i] == r {
                    for m in landNeighbors(i) where owner[m] != r && !around.contains(owner[m]) { around.append(owner[m]) }
                }
                guard let into = around.min(by: { size[$0] < size[$1] || (size[$0] == size[$1] && $0 < $1) }) else { continue }
                for i in 0..<n where owner[i] == r { owner[i] = into }
                merged = true
                break
            }
            if !merged { break }
        }

        // A territory may not ring another (or a lake): what it encloses becomes its own.
        for r in 0..<regionCount {
            guard owner.contains(r) else { continue }
            var outside = [Bool](repeating: false, count: n)
            var queue: [Int] = []
            for i in 0..<n where owner[i] != r && neighbors[i].contains(nil) {
                outside[i] = true
                queue.append(i)
            }
            var q = 0
            while q < queue.count {
                let c = queue[q]
                q += 1
                for m in neighbors[c].compactMap({ $0 }) where owner[m] != r && !outside[m] {
                    outside[m] = true
                    queue.append(m)
                }
            }
            for i in 0..<n where owner[i] != r && !outside[i] {
                owner[i] = r
                isLand[i] = true
            }
        }
        // Number the territories in board order.
        var renumber = [Int](repeating: -1, count: regionCount)
        var count = 0
        for i in 0..<n where owner[i] >= 0 && renumber[owner[i]] < 0 {
            renumber[owner[i]] = count
            count += 1
        }
        for i in 0..<n where owner[i] >= 0 { owner[i] = renumber[owner[i]] }
        regionCount = count
    }

    /// Water into sea zones; seas that touch no shore, or are tiny, join a neighbour.
    mutating func growSeas() {
        var seeds: [Int] = []
        let land = isLand
        for comp in components(where: { !land[$0] }) {
            let k = max(1, Int((Double(comp.count) / 95).rounded()))
            seeds += spreadSeeds(comp, k, passable: { !land[$0] })
        }
        let roughness = (0..<n).map { _ in unit() * 0.8 }
        seaOf = grow(seeds, passable: { !land[$0] }, cost: { _, b in 1 + roughness[b] })
        seaCount = seeds.count
        while true {
            var size = [Int](repeating: 0, count: seaCount)
            var shore = [Bool](repeating: false, count: seaCount)
            var contact = [[Int]](repeating: [Int](repeating: 0, count: seaCount), count: seaCount)
            for i in 0..<n where seaOf[i] >= 0 {
                size[seaOf[i]] += 1
                for m in neighbors[i].compactMap({ $0 }) {
                    if isLand[m] { shore[seaOf[i]] = true } else if seaOf[m] != seaOf[i] { contact[seaOf[i]][seaOf[m]] += 1 }
                }
            }
            let live = (0..<seaCount).filter { size[$0] > 0 }
            let tooMany = live.count > 14
            let smallest = live.min { size[$0] < size[$1] || (size[$0] == size[$1] && $0 < $1) }
            guard let s = live.first(where: { !shore[$0] || size[$0] < 25 }) ?? (tooMany ? smallest : nil),
                  let into = (0..<seaCount).filter({ contact[s][$0] > 0 }).max(by: { contact[s][$0] < contact[s][$1] || (contact[s][$0] == contact[s][$1] && $0 > $1) })
            else { break }
            for i in 0..<n where seaOf[i] == s { seaOf[i] = into }
        }
        var renumber = [Int](repeating: -1, count: seaCount)
        var count = 0
        for i in 0..<n where seaOf[i] >= 0 && renumber[seaOf[i]] < 0 {
            renumber[seaOf[i]] = count
            count += 1
        }
        for i in 0..<n where seaOf[i] >= 0 { seaOf[i] = renumber[seaOf[i]] }
        seaCount = count
    }

    // MARK: Everything else

    struct Region {
        var cells: [Int] = []
        var cx = 0.0, cy = 0.0
        var height = 0.0
        var touchesFrame = false
        /// Cells on the board's edge, where the outline is cut off.
        var edgeCells = 0
        var component = 0
        var riverEdges = 0
        var terrain = Terrain.plains
        var grain = 1
        var resources: [Resource: Int] = [:]
        var tags: [RegionTag] = []
        var id = ""
        var name = ""
        var climate = WorldNames.Climate.warm
        var capitalOf: Int?
        var homeland = false
    }

    // swiftlint:disable:next function_body_length
    mutating func finish() throws -> GameMap {
        let R = regionCount, S = seaCount
        guard (30...50).contains(R) else { throw Retry(reason: "\(R) territories") }
        guard S >= 5 else { throw Retry(reason: "\(S) seas") }

        var regions = [Region](repeating: Region(), count: R)
        for i in 0..<n where owner[i] >= 0 {
            let r = owner[i]
            regions[r].cells.append(i)
            let (x, y) = Self.center(i)
            regions[r].cx += x
            regions[r].cy += y
            regions[r].height += (elev[i] - threshold) / max(0.0001, topElev - threshold)
            if neighbors[i].contains(nil) { regions[r].touchesFrame = true; regions[r].edgeCells += 1 }
        }
        for r in 0..<R {
            let k = Double(regions[r].cells.count)
            regions[r].cx /= k
            regions[r].cy /= k
            regions[r].height /= k
        }
        let landComps = components(where: { isLand[$0] })
        for (k, comp) in landComps.enumerated() {
            for i in comp { regions[owner[i]].component = k }
        }

        // Who touches whom, and how much.
        var landContact = [[Int]](repeating: [Int](repeating: 0, count: R), count: R)
        var coast = [[Int]](repeating: [Int](repeating: 0, count: S), count: R)
        var seaContact = [[Int]](repeating: [Int](repeating: 0, count: S), count: S)
        for i in 0..<n {
            for m in neighbors[i].compactMap({ $0 }) where m > i {
                switch (owner[i] >= 0, owner[m] >= 0) {
                case (true, true) where owner[i] != owner[m]:
                    landContact[owner[i]][owner[m]] += 1
                    landContact[owner[m]][owner[i]] += 1
                case (true, false): coast[owner[i]][seaOf[m]] += 1
                case (false, true): coast[owner[m]][seaOf[i]] += 1
                case (false, false) where seaOf[i] != seaOf[m]:
                    seaContact[seaOf[i]][seaOf[m]] += 1
                    seaContact[seaOf[m]][seaOf[i]] += 1
                default: break
                }
            }
        }
        var landLinks: [(Int, Int, Crossing?)] = []
        for a in 0..<R { for b in (a + 1)..<max(a + 1, R) where landContact[a][b] > 0 { landLinks.append((a, b, nil)) } }
        func landAdjacency() -> [[Int]] {
            var adj = [[Int]](repeating: [], count: R)
            for (a, b, _) in landLinks { adj[a].append(b); adj[b].append(a) }
            return adj
        }
        func bfs(_ adj: [[Int]], from s: Int) -> [Int] {
            var d = [Int](repeating: Int.max, count: adj.count)
            d[s] = 0
            var queue = [s], q = 0
            while q < queue.count {
                let c = queue[q]
                q += 1
                for m in adj[c] where d[m] == Int.max { d[m] = d[c] + 1; queue.append(m) }
            }
            return d
        }

        // Straits: lands a channel's width apart, far apart (or apart altogether) by land.
        do {
            let adj = landAdjacency()
            var candidates: [(Int, Int)] = []
            for i in 0..<n where owner[i] < 0 {
                let around = neighbors[i].compactMap { $0 }.filter { owner[$0] >= 0 }.map { owner[$0] }
                for a in around { for b in around where a < b && landContact[a][b] == 0 && !candidates.contains(where: { $0 == (a, b) }) {
                    candidates.append((a, b))
                } }
            }
            candidates.shuffle(using: &rng)
            var joined: [(Int, Int)] = []
            for (a, b) in candidates where landLinks.filter({ $0.2 == .strait }).count < 6 {
                let ca = regions[a].component, cb = regions[b].component
                let far = bfs(adj, from: a)[b]
                if ca == cb, far != Int.max, far < 5 { continue }
                let key = (min(ca, cb), max(ca, cb))
                if ca != cb, joined.contains(where: { $0 == key }) { continue }
                joined.append(key)
                landLinks.append((a, b, .strait))
            }
        }

        // Rivers, down to the sea along cell edges.
        var vertexCells: [Int: [Int]] = [:]
        for i in 0..<n { for d in 0..<6 { vertexCells[vertex(i, d), default: []].append(i) } }
        var vertexNext: [Int: [Int]] = [:]
        for i in 0..<n {
            for d in 0..<6 {
                let a = vertex(i, d), b = vertex(i, (d + 1) % 6)
                if !(vertexNext[a]?.contains(b) ?? false) { vertexNext[a, default: []].append(b) }
                if !(vertexNext[b]?.contains(a) ?? false) { vertexNext[b, default: []].append(a) }
            }
        }
        let vertexKeys = vertexCells.keys.sorted()
        func allLand(_ v: Int) -> Bool { (vertexCells[v] ?? []).count == 3 && vertexCells[v]!.allSatisfy { isLand[$0] } }
        func shore(_ v: Int) -> Bool {
            let cells = vertexCells[v] ?? []
            return cells.contains { isLand[$0] } && cells.contains { !isLand[$0] }
        }
        func edgeCells(_ a: Int, _ b: Int) -> [Int] { (vertexCells[a] ?? []).filter { (vertexCells[b] ?? []).contains($0) } }
        var riverPaths: [[Int]] = []
        var riverLinks: [(Int, Int)] = []
        do {
            var best: [Int: Double] = [:], steps: [Int: Int] = [:], toward: [Int: Int] = [:]
            var noise: [Int: Double] = [:]
            for v in vertexKeys { noise[v] = unit() * 0.6 }
            var heap = Heap()
            for v in vertexKeys where shore(v) { best[v] = 0; steps[v] = 0; heap.push(0, v) }
            var done = Set<Int>()
            while !heap.isEmpty {
                let (d, v) = heap.pop()
                if done.contains(v) { continue }
                done.insert(v)
                for w in (vertexNext[v] ?? []).sorted() where allLand(w) && !done.contains(w) {
                    let h = (vertexCells[w]!.map { elev[$0] }.reduce(0, +) / 3 - threshold) / max(0.0001, topElev - threshold)
                    let nd = d + 1 + 6 * max(0, h) + noise[w]!
                    if nd < (best[w] ?? .infinity) {
                        best[w] = nd
                        steps[w] = steps[v]! + 1
                        toward[w] = v
                        heap.push(nd, w)
                    }
                }
            }
            var onRiver = Set<Int>()
            let wanted = 4 + int(3)
            let sources = vertexKeys.filter { (steps[$0] ?? 0) >= 7 }
            var tries = 0
            while riverPaths.count < wanted, tries < 40, !sources.isEmpty {
                tries += 1
                let s = sources[int(sources.count)]
                if onRiver.contains(s) { continue }
                // Not right beside another river's source.
                if riverPaths.contains(where: { path in
                    let (ax, ay) = Self.vertexUnits(path[0]), (bx, by) = Self.vertexUnits(s)
                    return abs(ax - bx) + abs(ay - by) < 12
                }) { continue }
                var path = [s]
                var v = s
                while let next = toward[v] {
                    path.append(next)
                    if onRiver.contains(next) { break }
                    v = next
                }
                guard path.count >= 6 else { continue }
                riverPaths.append(path)
                for v in path { onRiver.insert(v) }
                for k in 0..<(path.count - 1) {
                    let cells = edgeCells(path[k], path[k + 1])
                    let lands = cells.filter { owner[$0] >= 0 }.map { owner[$0] }
                    for r in Set(lands).sorted() { regions[r].riverEdges += 1 }
                    if lands.count == 2, lands[0] != lands[1] {
                        let pair = (min(lands[0], lands[1]), max(lands[0], lands[1]))
                        if !riverLinks.contains(where: { $0 == pair }) { riverLinks.append(pair) }
                    }
                }
            }
        }
        for k in landLinks.indices where landLinks[k].2 == nil && riverLinks.contains(where: { $0 == (landLinks[k].0, landLinks[k].1) }) {
            landLinks[k].2 = .river
        }

        // Distances: by land, and by land and sea (a sea crossing counts two).
        let adj = landAdjacency()
        let landDist = (0..<R).map { bfs(adj, from: $0) }
        var both = adj + [[Int]](repeating: [], count: S)
        for r in 0..<R { for s in 0..<S where coast[r][s] > 0 { both[r].append(R + s); both[R + s].append(r) } }
        for a in 0..<S { for b in 0..<S where a != b && seaContact[a][b] > 0 { both[R + a].append(R + b) } }
        let anyDist = (0..<R).map { Array(bfs(both, from: $0).prefix(R)) }
        guard anyDist[0].allSatisfy({ $0 != Int.max }) else { throw Retry(reason: "unreachable land") }
        let regionsInComponent = (0..<landComps.count).map { c in regions.filter { $0.component == c }.count }
        func coastal(_ r: Int) -> Bool { coast[r].contains { $0 > 0 } }
        func island(_ r: Int) -> Bool { regionsInComponent[regions[r].component] == 1 }

        // Terrain: the highest lands are mountains and hills; the dry south desert, the wet north forest.
        let byHeight = (0..<R).sorted { regions[$0].height > regions[$1].height || (regions[$0].height == regions[$1].height && $0 < $1) }
        let mountains = min(5, max(2, Int((Double(R) * 0.1 + (unit() - 0.5) * 2).rounded())))
        let hills = Int((Double(R) * 0.27).rounded())
        var placed = 0
        var assigned = [Bool](repeating: false, count: R)
        for r in byHeight where placed < mountains && !island(r) && regions[r].cells.count >= 9 {
            regions[r].terrain = .mountains
            assigned[r] = true
            placed += 1
        }
        placed = 0
        for r in byHeight where !assigned[r] && placed < hills {
            regions[r].terrain = .hills
            assigned[r] = true
            placed += 1
        }
        let shift = (unit() - 0.5) * 0.12
        let wetSalt = UInt64(int(1 << 30))
        var latitude = [Double](repeating: 0, count: R)
        for r in 0..<R {
            latitude[r] = (regions[r].cy - Self.minY) / (Self.maxY - Self.minY) + shift
            guard !assigned[r] else { continue }
            let wet = fbm(regions[r].cx / 300, regions[r].cy / 300, wetSalt)
            if latitude[r] > 0.86 || (latitude[r] > 0.64 && wet < 0.58) {
                regions[r].terrain = .desert
            } else if wet > 0.66 || (latitude[r] < 0.38 && wet > 0.42) {
                regions[r].terrain = .forest
            }
        }

        // The empires' starts: coasts on big enough lands, far apart, with room to grow; the
        // river empires on a river.
        let civs = template.civilizations
        let homes = civs.map { template.territory($0.capital)! }
        let candidates = (0..<R).filter { coastal($0) && !island($0) && regionsInComponent[regions[$0].component] >= 4
            && regions[$0].terrain != .mountains && regions[$0].cells.count >= 9
            && regions[$0].edgeCells * 4 <= regions[$0].cells.count }
        guard candidates.count >= civs.count * 2 else { throw Retry(reason: "too few starts") }
        let riverSites = candidates.filter { regions[$0].riverEdges >= 2 }
        var pick: [Int] = []
        var bestScore = -Double.infinity
        for _ in 0..<900 {
            var tuple: [Int] = []
            for home in homes {
                let pool = home.has(.riverValley) && riverSites.count >= 3 ? riverSites : candidates
                let free = pool.filter { !tuple.contains($0) }
                guard !free.isEmpty else { break }
                tuple.append(free[int(free.count)])
            }
            guard tuple.count == homes.count else { continue }
            var minAny = Int.max, minLand = Int.max
            for (i, a) in tuple.enumerated() { for b in tuple[(i + 1)...] {
                minAny = min(minAny, anyDist[a][b])
                minLand = min(minLand, landDist[a][b])
            } }
            guard minAny >= 3, minLand >= 3 else { continue }
            var share = [Int](repeating: 0, count: tuple.count)
            for r in 0..<R where !tuple.contains(r) {
                let d = tuple.map { anyDist[r][$0] }
                let low = d.min()!
                if d.filter({ $0 == low }).count == 1 { share[d.firstIndex(of: low)!] += 1 }
            }
            let room = tuple.map { c in (0..<R).filter { $0 != c && !tuple.contains($0) && landDist[c][$0] <= 2 }.count }
            guard room.min()! >= 2 else { continue }
            let rivers = zip(homes, tuple).filter { $0.0.has(.riverValley) && regions[$0.1].riverEdges >= 2 }.count
            // A poor, rocky capital (Greece) lives by the sea: it wants a peninsula, few land
            // borders to hold and more than one sea to sail.
            let shelter = zip(homes, tuple).filter { $0.0.grain <= 4 }.map { _, r -> Double in
                let borders = adj[r].count, waters = coast[r].filter { $0 > 0 }.count
                return (borders <= 2 ? 3 : 0) - Double(max(0, borders - 2)) + Double(min(waters - 1, 2))
            }.reduce(0, +)
            let score = 4 * Double(min(minAny, 7)) + 1.5 * Double(min(minLand, 6)) - 1.2 * Double(share.max()! - share.min()!)
                + 3 * Double(rivers) + shelter + Double(min(room.min()!, 4)) + unit() * 0.5
            if score > bestScore { bestScore = score; pick = tuple }
        }
        guard pick.count == civs.count else { throw Retry(reason: "no fair starts") }
        for (k, r) in pick.enumerated() { regions[r].capitalOf = k }
        let capitalDistance = (0..<R).map { r in pick.map { anyDist[r][$0] }.min()! }

        // Wandering tribes on the far edges of the world.
        let homelandCount = Int((Double(R) * 0.18).rounded())
        let tribal = (0..<R).filter { regions[$0].capitalOf == nil && capitalDistance[$0] >= 3 && regions[$0].terrain != .mountains }
            .map { r in (r, Double(capitalDistance[r]) + (regions[r].touchesFrame ? 2 : 0) + (island(r) ? -3 : 0) + unit()) }
            .sorted { $0.1 > $1.1 || ($0.1 == $1.1 && $0.0 < $1.0) }
        for (r, _) in tribal.prefix(homelandCount) {
            regions[r].homeland = true
            regions[r].tags.append(.barbarianHomeland)
        }

        // Grain. The plains a river runs through are breadbaskets.
        let valleys = (0..<R).filter { regions[$0].capitalOf == nil && !regions[$0].homeland && regions[$0].riverEdges >= 3
            && (regions[$0].terrain == .plains || regions[$0].terrain == .desert) }
            .sorted { regions[$0].riverEdges > regions[$1].riverEdges || (regions[$0].riverEdges == regions[$1].riverEdges && $0 < $1) }
            .prefix(3)
        for r in valleys {
            regions[r].terrain = .plains
            regions[r].tags.append(.riverValley)
        }
        for r in 0..<R {
            let big = regions[r].cells.count >= 24 ? 1 : 0
            switch regions[r].terrain {
            case .plains: regions[r].grain = 3 + int(3) + big
            case .hills: regions[r].grain = 2 + int(2)
            case .forest: regions[r].grain = 2 + int(2) + big
            case .mountains: regions[r].grain = 1
            case .desert: regions[r].grain = 1 + (int(3) == 0 ? 1 : 0)
            }
            if regions[r].tags.contains(.riverValley) { regions[r].grain += 2 }
        }
        for (k, r) in pick.enumerated() {
            let home = homes[k]
            regions[r].terrain = home.terrain
            regions[r].grain = home.grain
            regions[r].resources = home.resources
            regions[r].tags = home.tags ?? []
        }

        // Goods, scattered by terrain. Tin is rare and never next to a capital.
        let scale = Double(R - civs.count) / 36
        let totals: [(Resource, Int)] = [(.stone, 14), (.horses, 15), (.iron, 10), (.copper, 9), (.timber, 9),
                                         (.gold, 8), (.wine, 7), (.luxuries, 7)]
        func weight(_ r: Int, _ res: Resource) -> Double {
            let g = regions[r]
            guard g.capitalOf == nil else { return 0 }
            let t = g.terrain, lat = latitude[r]
            var w: Double
            switch res {
            case .copper: w = [.mountains: 4, .hills: 3][t] ?? 0.6
                if island(r) { w *= 1.6 }
            case .tin: w = [.mountains: 2, .hills: 2, .forest: 2][t] ?? 1
            case .iron: w = [.mountains: 3, .hills: 3, .forest: 2, .plains: 0.7][t] ?? 0.3
            case .horses: w = [.plains: 3, .hills: 1, .desert: 0.8][t] ?? 0.5
                if g.homeland { w *= 2 }
            case .timber: w = [.forest: 5, .hills: 1.5, .mountains: 1, .plains: 0.4][t] ?? 0
            case .gold: w = [.mountains: 3, .hills: 2, .desert: 1.5, .forest: 1][t] ?? 0.5
            case .wine: w = [.hills: 3, .plains: 2, .forest: 0.3][t] ?? 0
                if lat < 0.25 || lat > 0.8 { w *= 0.3 }
                if coastal(r) { w *= 2 }
            case .luxuries: w = [.desert: 3, .plains: lat > 0.55 ? 1.5 : 0.3][t] ?? 0.3
                if coastal(r) { w *= 1.5 }
            case .stone: w = [.mountains: 4, .hills: 3, .desert: 1][t] ?? 0.5
            case .grain: w = 0
            }
            let have = g.resources[res] ?? 0, all = g.resources.values.reduce(0, +)
            if all >= 4 { return 0 }
            return w / (1 + Double(have) * 1.5) / (1 + Double(all) * 0.4)
        }
        func place(_ res: Resource, among allowed: [Int]) {
            let w = allowed.map { weight($0, res) }
            let total = w.reduce(0, +)
            guard total > 0 else { return }
            var x = unit() * total
            for (k, r) in allowed.enumerated() {
                x -= w[k]
                if x <= 0 || k == allowed.count - 1 {
                    regions[r].resources[res, default: 0] += 1
                    return
                }
            }
        }
        let all = Array(0..<R)
        for (res, count) in totals {
            for _ in 0..<max(1, Int((Double(count) * scale).rounded())) { place(res, among: all) }
        }
        // Tin: two or three far-off lodes, never a capital's neighbour, so the hunt differs each game.
        let far = all.filter { capitalDistance[$0] >= 2 }
        let lodes = 2 + int(2)
        var tinSites: [Int] = []
        for _ in 0..<lodes {
            let open = far.filter { r in !tinSites.contains(where: { anyDist[r][$0] < 3 }) }
            let before = all.map { regions[$0].resources[.tin] ?? 0 }
            place(.tin, among: open.isEmpty ? far : open)
            if let r = all.first(where: { (regions[$0].resources[.tin] ?? 0) > before[$0] }) { tinSites.append(r) }
        }
        if lodes == 2, let r = tinSites.first { regions[r].resources[.tin, default: 0] += 1 }
        // Every empire has copper within three steps.
        for r in pick where !all.contains(where: { (regions[$0].resources[.copper] ?? 0) > 0 && anyDist[r][$0] <= 3 }) {
            let near = all.filter { regions[$0].capitalOf == nil && anyDist[r][$0] >= 2 && anyDist[r][$0] <= 3 }
            place(.copper, among: near.isEmpty ? all.filter { regions[$0].capitalOf == nil } : near)
        }

        // Names, peoples and ids.
        for r in 0..<R {
            let t = regions[r].terrain
            regions[r].climate = island(r) ? .sea
                : t == .mountains || t == .hills ? .high
                : t == .desert ? .dry
                : t == .forest || latitude[r] < 0.35 ? .cold
                : latitude[r] > 0.72 ? .dry : .warm
        }
        var lands = WorldNames.lands
        var tribes = WorldNames.homelands
        var peoples: [TerritoryID: People] = [:]
        var naming = Array(0..<R)
        naming.shuffle(using: &rng)
        for r in naming {
            if let k = regions[r].capitalOf {
                regions[r].id = civs[k].id
                regions[r].name = homes[k].name
            } else if regions[r].homeland {
                let w = tribes.map { $0.climate == regions[r].climate ? 20.0 : 1.0 }
                let k = weightedIndex(w)
                regions[r].name = tribes.remove(at: k).name
            } else {
                let w = lands.map { $0.climate == regions[r].climate ? 20.0 : 1.0 }
                let land = lands.remove(at: weightedIndex(w))
                regions[r].name = land.land
                regions[r].id = Self.slug(land.land)
                peoples[regions[r].id] = People(name: land.people, ruler: land.ruler, temperament: land.temperament, look: land.look)
            }
            if regions[r].id.isEmpty { regions[r].id = Self.slug(regions[r].name) }
        }
        var seaNames = WorldNames.seas
        seaNames.shuffle(using: &rng)
        let seaIDs = (0..<S).map { "sea_\($0 + 1)" }

        // Chokepoints: narrow waters held from their shores, and mountain passes.
        var chokepoints: [Chokepoint] = []
        var narrows: [(width: Int, a: Int, b: Int, held: [Int])] = []
        for a in 0..<S { for b in (a + 1)..<max(a + 1, S) where (1...3).contains(seaContact[a][b]) {
            var held: [Int] = []
            for i in 0..<n where seaOf[i] == a || seaOf[i] == b {
                let other = seaOf[i] == a ? b : a
                guard neighbors[i].contains(where: { $0.map { seaOf[$0] == other } ?? false }) else { continue }
                for m in neighbors[i].compactMap({ $0 }) where owner[m] >= 0 {
                    let r = owner[m]
                    if coast[r][a] > 0, coast[r][b] > 0, !held.contains(r) { held.append(r) }
                }
            }
            if (1...2).contains(held.count) { narrows.append((seaContact[a][b], a, b, held.sorted())) }
        } }
        for k in narrows.sorted(by: { ($0.width, $0.a, $0.b) < ($1.width, $1.a, $1.b) }).prefix(3) {
            chokepoints.append(Chokepoint(id: "narrows_\(chokepoints.count + 1)", name: "Straits of \(regions[k.held[0]].name)",
                                          heldBy: k.held.map { regions[$0].id }, gatesSeaLink: [seaIDs[k.a], seaIDs[k.b]]))
        }
        for r in 0..<R where regions[r].terrain == .mountains && adj[r].count >= 2 && chokepoints.count < 7 {
            chokepoints.append(Chokepoint(id: "pass_\(regions[r].id)", name: "\(regions[r].name) Passes",
                                          heldBy: [regions[r].id], gatesSeaLink: nil))
        }

        // The art: smoothed outlines, labels, rivers and peaks.
        var position: [Int: (Double, Double)] = [:]
        for v in vertexKeys {
            let (vx, vy) = Self.vertexUnits(v)
            var (x, y) = Self.point(vx, vy)
            x += (hash(vx, vy, 11) - 0.5) * 9
            y += (hash(vx, vy, 12) - 0.5) * 9
            position[v] = (min(Self.maxX, max(Self.minX, x)), min(Self.maxY, max(Self.minY, y)))
        }
        func junction(_ v: Int) -> Bool {
            let cells = vertexCells[v] ?? []
            var kinds = cells.map { owner[$0] >= 0 ? owner[$0] : -1 }
            if cells.count < 3 { kinds.append(-2) }
            return Set(kinds).count == 3
        }
        func rounded(_ p: (Double, Double)) -> [Double] { [(p.0 * 10).rounded() / 10, (p.1 * 10).rounded() / 10] }
        func lerp(_ a: Int, _ b: Int, _ t: Double) -> [Double] {
            let p = position[a]!, q = position[b]!
            return rounded((p.0 + (q.0 - p.0) * t, p.1 + (q.1 - p.1) * t))
        }
        /// One pass of corner cutting, keeping the corners where three owners meet, so neighbours'
        /// outlines still share every point.
        func smooth(_ loop: [Int], closed: Bool) -> [[Double]] {
            var out: [[Double]] = []
            let count = loop.count
            for k in 0..<(closed ? count : count - 1) {
                let a = loop[k], b = loop[(k + 1) % count]
                if junction(a) || (!closed && k == 0) { out.append(rounded(position[a]!)) }
                out.append(lerp(a, b, 0.25))
                out.append(lerp(a, b, 0.75))
            }
            if !closed { out.append(rounded(position[loop[count - 1]]!)) }
            return out
        }
        func pole(_ cells: [Int], inside: (Int) -> Bool, cx: Double, cy: Double) -> (cell: Int, depth: [Int: Int]) {
            var depth: [Int: Int] = [:]
            var queue: [Int] = []
            for c in cells where neighbors[c].contains(where: { $0.map { !inside($0) } ?? true }) {
                depth[c] = 0
                queue.append(c)
            }
            var q = 0
            while q < queue.count {
                let c = queue[q]
                q += 1
                for m in neighbors[c].compactMap({ $0 }) where inside(m) && depth[m] == nil {
                    depth[m] = depth[c]! + 1
                    queue.append(m)
                }
            }
            var best = cells[0], bestScore = -Double.infinity
            for c in cells {
                let (x, y) = Self.center(c)
                let up = neighbors[c][4].map(inside) ?? false, down = neighbors[c][1].map(inside) ?? false
                let score = Double(depth[c] ?? 0) * 10 + (up ? 3 : 0) + (down ? 3 : 0)
                    - (neighbors[c].contains(nil) ? 20 : 0)
                    - ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot() * 0.02
                if score > bestScore { bestScore = score; best = c }
            }
            return (best, depth)
        }
        var shapes: [TerritoryID: MapArt.Shape] = [:]
        var peaks: [TerritoryID: [[Double]]] = [:]
        for r in 0..<R {
            var next: [Int: Int] = [:]
            for c in regions[r].cells {
                for d in 0..<6 where neighbors[c][d].map({ owner[$0] != r }) ?? true {
                    next[vertex(c, d)] = vertex(c, (d + 1) % 6)
                }
            }
            guard let start = next.keys.min() else { throw Retry(reason: "empty territory") }
            var loop = [start]
            var v = next[start]!
            while v != start {
                loop.append(v)
                guard let w = next[v], loop.count <= next.count else { throw Retry(reason: "tangled outline") }
                v = w
            }
            guard loop.count == next.count else { throw Retry(reason: "territory with a hole") }
            let (cell, depth) = pole(regions[r].cells, inside: { owner[$0] == r }, cx: regions[r].cx, cy: regions[r].cy)
            let (x, y) = Self.center(cell)
            let id = regions[r].id
            // Name above, army below: a full cell apart where the land runs on, else within the cell.
            let up = neighbors[cell][4].map { owner[$0] == r } ?? false
            let down = neighbors[cell][1].map { owner[$0] == r } ?? false
            let outline = smooth(loop, closed: true)
            func within(_ offsets: [Double]) -> [Double] {
                for dy in offsets where Self.inside((x, y + dy), outline) { return rounded((x, y + dy)) }
                return rounded((x, y))
            }
            shapes[id] = MapArt.Shape(polygon: outline, label: within((up ? [-16] : []) + [-7, -4, -1, 2]), angle: 0,
                                      token: within((down ? [16] : []) + [7, 4, 1, -2]))
            if regions[r].terrain == .mountains {
                var chosen: [Int] = []
                let avoid = [cell] + [neighbors[cell][1], neighbors[cell][4]].compactMap { $0 }
                for c in regions[r].cells.sorted(by: { (depth[$0] ?? 0, $1) > (depth[$1] ?? 0, $0) })
                where !avoid.contains(c) && chosen.count < 4 && !chosen.contains(where: { neighbors[c].contains($0) }) {
                    chosen.append(c)
                }
                peaks[id] = chosen.map { c in
                    let (px, py) = Self.center(c)
                    return rounded((px + (hash(c, 1, 13) - 0.5) * 8, py + (hash(c, 2, 13) - 0.5) * 6))
                }
            }
        }
        var seaLabels: [SeaZoneID: [Double]] = [:]
        for s in 0..<S {
            let cells = (0..<n).filter { seaOf[$0] == s }
            let (cx, cy) = cells.map(Self.center).reduce((0.0, 0.0)) { ($0.0 + $1.0 / Double(cells.count), $0.1 + $1.1 / Double(cells.count)) }
            let (cell, _) = pole(cells, inside: { seaOf[$0] == s }, cx: cx, cy: cy)
            seaLabels[seaIDs[s]] = rounded(Self.center(cell))
        }
        let rivers = riverPaths.map { smooth($0, closed: false) }
        let art = MapArt(size: [2000, 924], territories: shapes, seas: seaLabels, rivers: rivers, peaks: peaks)

        let territories = (0..<R).map { r in
            Territory(id: regions[r].id, name: regions[r].name, terrain: regions[r].terrain, grain: max(1, regions[r].grain),
                      resources: regions[r].resources.filter { $0.value > 0 },
                      seas: (0..<S).filter { coast[r][$0] > 0 }.map { seaIDs[$0] },
                      tags: regions[r].tags.isEmpty ? nil : regions[r].tags)
        }
        let links = landLinks.map { LandLink(a: regions[$0.0].id, b: regions[$0.1].id, crossing: $0.2) }
        var seaLinks: [[SeaZoneID]] = []
        for a in 0..<S { for b in (a + 1)..<max(a + 1, S) where seaContact[a][b] > 0 { seaLinks.append([seaIDs[a], seaIDs[b]]) } }
        let seas = (0..<S).map { SeaZone(id: seaIDs[$0], name: seaNames[$0 % seaNames.count]) }
        let empires = civs.map { Civilization(id: $0.id, name: $0.name, capital: $0.id, government: $0.government) }
        return try GameMap(version: WorldGenerator.mapVersion, territories: territories, landLinks: links, seas: seas,
                           seaLinks: seaLinks, chokepoints: chokepoints, civilizations: empires, peoples: peoples,
                           art: art, worldSeed: seed)
    }

    mutating func weightedIndex(_ weights: [Double]) -> Int {
        var x = unit() * weights.reduce(0, +)
        for (k, w) in weights.enumerated() {
            x -= w
            if x <= 0 { return k }
        }
        return weights.count - 1
    }

    static func inside(_ p: (Double, Double), _ polygon: [[Double]]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            if (a[1] > p.1) != (b[1] > p.1), p.0 < (b[0] - a[0]) * (p.1 - a[1]) / (b[1] - a[1]) + a[0] { inside.toggle() }
            j = i
        }
        return inside
    }

    static func slug(_ name: String) -> String {
        String(name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" })
    }
}

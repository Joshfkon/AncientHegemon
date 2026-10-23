/// How a map is drawn: territory outlines, where names and army tokens sit, sea labels, rivers
/// and peaks, in board coordinates (the classic board's photo pixels: x 100–1905, y 5–920).
/// The classic board's art ships with the app (map_shapes.json, the same format); a generated
/// world carries its own.
public struct MapArt: Codable, Sendable, Equatable {
    public struct Shape: Codable, Sendable, Equatable {
        public let polygon: [[Double]]
        public let label: [Double]
        /// Lettering angle, in degrees clockwise.
        public let angle: Double
        /// Where the army token sits.
        public let token: [Double]

        public init(polygon: [[Double]], label: [Double], angle: Double, token: [Double]) {
            self.polygon = polygon
            self.label = label
            self.angle = angle
            self.token = token
        }
    }

    public let size: [Double]
    public let territories: [TerritoryID: Shape]
    /// Where each sea's name and fleets are drawn.
    public let seas: [SeaZoneID: [Double]]
    public let rivers: [[[Double]]]
    public let peaks: [TerritoryID: [[Double]]]
    /// Where the painted board's two halves meet (the classic board only).
    public let seam: Double?

    public init(size: [Double], territories: [TerritoryID: Shape], seas: [SeaZoneID: [Double]],
                rivers: [[[Double]]], peaks: [TerritoryID: [[Double]]], seam: Double? = nil) {
        self.size = size
        self.territories = territories
        self.seas = seas
        self.rivers = rivers
        self.peaks = peaks
        self.seam = seam
    }
}

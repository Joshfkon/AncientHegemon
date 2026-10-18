/// The Late Bronze Age collapse: an escalating arc of disasters (DESIGN, Late Bronze Age redesign).
///
/// Pressure is 0 before `startRound`, climbs linearly to 100 at `peakRound`, and stays there.
/// Collapse events join the ordinary event table with weights scaled by pressure, and the
/// chance of drawing an event at all rises with it.
public struct CollapseRules: Codable, Sendable, Equatable {
    public let startRound: Int
    public let peakRound: Int
    /// Extra percent chance of an event at full pressure.
    public let extraChancePercent: Int
    /// Bronze lost each harvest (percent, rounded up): it needs a steady tin supply to keep up.
    public let bronzeWearPercent: Int
    /// Sea Peoples raids land `seaPeoplesBase + pressure / seaPeoplesPressurePerExtra` units.
    public let seaPeoplesBase: Int
    public let seaPeoplesPressurePerExtra: Int
    /// A drought cuts the harvest of this many territories to this percent.
    public let droughtGrainPercent: Int
    public let droughtTerritories: Int
    public let earthquakePopulation: Int
    /// Rounds a broken trade route stays broken.
    public let disruptionRounds: Int
    public let weights: CollapseWeights
}

/// Weights at full pressure.
public struct CollapseWeights: Codable, Sendable, Equatable {
    public let seaPeoplesPerCoast: Int
    public let drought: Int
    public let droughtNoRiver: Int
    public let earthquake: Int
    public let earthquakePerRugged: Int
    public let tradeDisruptionPerRoute: Int
}

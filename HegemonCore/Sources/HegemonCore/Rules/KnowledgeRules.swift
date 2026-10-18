/// Fields of knowledge. Nobody chooses what to learn: knowledge flows into the fields an empire
/// has experience in, and contact with more advanced neighbors passes theirs along.
public enum KnowledgeField: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case agriculture, metallurgy, horsemanship, seafaring, construction, warfare, administration
}

public struct KnowledgeEffects: Codable, Sendable, Equatable {
    // Agriculture
    public let irrigationRiverGrain: Int
    public let granaryTurns: Int
    public let cropRotationFarmGrain: Int
    // Metallurgy (level 2, ironworking, makes iron usable)
    public let bronzeCastingPercent: Int
    public let steelIronWeight: Int
    // Horsemanship
    public let chariotsPercent: Int
    public let breedingMultiplier: Int
    public let horseArchersPercent: Int
    // Seafaring
    public let galleysCapacity: Int
    public let navigationPercent: Int
    public let triremesPercent: Int
    // Construction
    public let masonryTurns: Int
    public let fortificationPercent: Int
    public let engineeringDiscount: Int
    // Warfare
    public let drillPercent: Int
    public let bowsPercent: Int
    public let tacticsMorale: Int
    // Administration
    public let writingLoyalty: Int
    public let coinagePercent: Int
    public let lawLegitimacy: Int
}

public struct KnowledgeRules: Codable, Sendable, Equatable {
    /// Knowledge points a turn: population / populationPerPoint + income / goldPerPoint.
    /// Progress is kept in tenths of a point so small shares still count.
    public let populationPerPoint: Int
    public let goldPerPoint: Int
    /// Experience fades by this share each turn, so direction follows recent practice.
    public let experienceDecayPercent: Int
    /// Share of a neighbor's lead in a field passed along each turn (more between trade partners).
    public let contactDiffusionPercent: Int
    public let tradeDiffusionPercent: Int
    /// Progress needed for levels 1, 2 and 3, in tenths of a knowledge point.
    public let levels: [Int]
    /// Names of each field's levels.
    public let fields: [KnowledgeField: [String]]
    public let effects: KnowledgeEffects
}

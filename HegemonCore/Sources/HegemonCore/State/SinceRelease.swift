/// A saved field added after the first release (1.0): a save that predates it decodes the field
/// as empty instead of failing, so updates keep players' games. Every field added to `GameState`
/// from 1.0 on should carry it (or be optional).
@propertyWrapper
public struct SinceRelease<Value: Codable & Sendable & Equatable & EmptyForOldSaves>: Codable, Sendable, Equatable {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init(from decoder: Decoder) throws { wrappedValue = try decoder.singleValueContainer().decode(Value.self) }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}

/// What a field reads as in a save from before it existed.
public protocol EmptyForOldSaves { static var emptyForOldSaves: Self { get } }
extension Array: EmptyForOldSaves { public static var emptyForOldSaves: Self { [] } }
extension Dictionary: EmptyForOldSaves { public static var emptyForOldSaves: Self { [:] } }
extension Set: EmptyForOldSaves { public static var emptyForOldSaves: Self { [] } }

extension KeyedDecodingContainer {
    public func decode<V>(_ type: SinceRelease<V>.Type, forKey key: Key) throws -> SinceRelease<V> {
        try decodeIfPresent(type, forKey: key) ?? SinceRelease(wrappedValue: .emptyForOldSaves)
    }
}

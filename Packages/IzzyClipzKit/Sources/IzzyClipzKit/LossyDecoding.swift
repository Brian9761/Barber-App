import Foundation

/// Decodes a value if it can, and `nil` instead of failing if it can't.
///
/// Wrapping array elements in this lets one bad entry be skipped without
/// losing the rest of the list.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

extension Array {
    /// The elements that decoded, in order.
    func decodedValues<Value>() -> [Value] where Element == Lossy<Value> {
        compactMap(\.value)
    }
}

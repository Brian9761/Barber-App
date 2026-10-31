import Foundation
import XCTest
@testable import IzzyClipzKit

/// Any JSON value, for comparing documents regardless of key order or spacing.
enum JSONValue: Equatable, Decodable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    init(data: Data) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    var description: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return String(value)
        case .number(let value): return value.rounded() == value && abs(value) < 1e15 ? String(Int(value)) : String(value)
        case .string(let value): return "\"\(value)\""
        case .array(let values): return "[" + values.map(\.description).joined(separator: ", ") + "]"
        case .object(let members):
            return "{" + members.keys.sorted().map { "\"\($0)\": \(members[$0]!)" }.joined(separator: ", ") + "}"
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    var keys: Set<String> {
        if case .object(let members) = self { return Set(members.keys) }
        return []
    }

    /// Every place `other` differs from `self`, as "path: expected … got …".
    func differences(from other: JSONValue, at path: String = "$") -> [String] {
        switch (self, other) {
        case (.object(let lhs), .object(let rhs)):
            var result: [String] = []
            for key in Set(lhs.keys).union(rhs.keys).sorted() {
                switch (lhs[key], rhs[key]) {
                case (let left?, let right?): result += left.differences(from: right, at: "\(path).\(key)")
                case (let left?, nil): result.append("\(path).\(key): only in the first (\(left))")
                case (nil, let right?): result.append("\(path).\(key): only in the second (\(right))")
                case (nil, nil): break
                }
            }
            return result
        case (.array(let lhs), .array(let rhs)):
            guard lhs.count == rhs.count else { return ["\(path): \(lhs.count) items vs \(rhs.count)"] }
            return zip(lhs, rhs).enumerated().flatMap { index, pair in pair.0.differences(from: pair.1, at: "\(path)[\(index)]") }
        default:
            return self == other ? [] : ["\(path): \(self) vs \(other)"]
        }
    }
}

enum TestPaths {
    /// The package folder, `Packages/IzzyClipzKit`.
    static let package = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // API
        .deletingLastPathComponent() // IzzyClipzKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // IzzyClipzKit

    /// The repository root, two levels above the package.
    static let repository = package.deletingLastPathComponent().deletingLastPathComponent()

    /// The Kit's own fixtures, written by hand from the contract.
    static let kitFixtures = package.appendingPathComponent("Tests/IzzyClipzKitTests/Fixtures")

    /// The server's fixtures, one per response type, when the server is in the repo.
    static let serverFixtures = repository.appendingPathComponent("server/test/fixtures/contract")

    static func jsonFiles(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { folder.appendingPathComponent($0) }
    }
}

func kitFixture(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
    let url = TestPaths.kitFixtures.appendingPathComponent(name)
    guard let data = FileManager.default.contents(atPath: url.path) else {
        XCTFail("Missing fixture \(url.path)", file: file, line: line)
        throw CocoaError(.fileNoSuchFile)
    }
    return data
}

func decodeAPI<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try IzzyAPI.makeDecoder().decode(type, from: Data(json.utf8))
}

func encodeAPI<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONValue(data: IzzyAPI.makeEncoder().encode(value))
}

/// A UTC moment, e.g. `utc(2026, 11, 2, 18)` for 2026-11-02T18:00:00Z.
func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

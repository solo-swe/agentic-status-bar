import Foundation

/// JSON that keeps object key order and number spelling, for editing files people also edit by hand
/// (~/.claude/settings.json). Foundation's JSONSerialization loses both.
public indirect enum OrderedJSON: Equatable, Sendable {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// The number as written.
    case number(String)
    case bool(Bool)
    case null

    public static func == (a: OrderedJSON, b: OrderedJSON) -> Bool {
        switch (a, b) {
        case let (.object(x), .object(y)): x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case let (.array(x), .array(y)): x == y
        case let (.string(x), .string(y)): x == y
        case let (.number(x), .number(y)): x == y
        case let (.bool(x), .bool(y)): x == y
        case (.null, .null): true
        default: false
        }
    }

    // MARK: Access

    public subscript(key: String) -> OrderedJSON? {
        get {
            guard case .object(let pairs) = self else { return nil }
            return pairs.first { $0.0 == key }?.1
        }
        set {
            guard case .object(var pairs) = self else { return }
            if let i = pairs.firstIndex(where: { $0.0 == key }) {
                if let newValue { pairs[i].1 = newValue } else { pairs.remove(at: i) }
            } else if let newValue {
                pairs.append((key, newValue))
            }
            self = .object(pairs)
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var arrayValue: [OrderedJSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    // MARK: Parsing

    public struct ParseError: Error, Equatable {
        public var offset: Int
    }

    public static func parse(_ data: Data) throws -> OrderedJSON {
        var parser = Parser(bytes: Array(data))
        parser.skipSpace()
        let value = try parser.value()
        parser.skipSpace()
        guard parser.i == parser.bytes.count else { throw ParseError(offset: parser.i) }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0

        mutating func skipSpace() {
            while i < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[i]) { i += 1 }
        }

        func fail() -> ParseError { ParseError(offset: i) }

        mutating func expect(_ literal: String) throws {
            let lit = Array(literal.utf8)
            guard i + lit.count <= bytes.count, Array(bytes[i..<i + lit.count]) == lit else { throw fail() }
            i += lit.count
        }

        mutating func value() throws -> OrderedJSON {
            guard i < bytes.count else { throw fail() }
            switch bytes[i] {
            case UInt8(ascii: "{"): return try object()
            case UInt8(ascii: "["): return try array()
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            default: return try number()
            }
        }

        mutating func object() throws -> OrderedJSON {
            i += 1
            var pairs: [(String, OrderedJSON)] = []
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
            while true {
                skipSpace()
                guard i < bytes.count, bytes[i] == UInt8(ascii: "\"") else { throw fail() }
                let key = try string()
                skipSpace()
                try expect(":")
                skipSpace()
                pairs.append((key, try value()))
                skipSpace()
                guard i < bytes.count else { throw fail() }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "}") { i += 1; return .object(pairs) }
                throw fail()
            }
        }

        mutating func array() throws -> OrderedJSON {
            i += 1
            var items: [OrderedJSON] = []
            skipSpace()
            if i < bytes.count, bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
            while true {
                skipSpace()
                items.append(try value())
                skipSpace()
                guard i < bytes.count else { throw fail() }
                if bytes[i] == UInt8(ascii: ",") { i += 1; continue }
                if bytes[i] == UInt8(ascii: "]") { i += 1; return .array(items) }
                throw fail()
            }
        }

        mutating func string() throws -> String {
            let start = i
            i += 1
            var escaped = false
            while i < bytes.count {
                let c = bytes[i]
                if escaped { escaped = false } else if c == UInt8(ascii: "\\") { escaped = true } else if c == UInt8(ascii: "\"") { break }
                i += 1
            }
            guard i < bytes.count else { throw fail() }
            i += 1
            // The raw token, decoded by Foundation for escapes and surrogate pairs.
            let token = Data(bytes[start..<i])
            guard let s = try? JSONSerialization.jsonObject(with: token, options: [.fragmentsAllowed]) as? String else { throw fail() }
            return s
        }

        mutating func number() throws -> OrderedJSON {
            let start = i
            while i < bytes.count, "+-0123456789.eE".utf8.contains(bytes[i]) { i += 1 }
            let raw = String(decoding: bytes[start..<i], as: UTF8.self)
            guard !raw.isEmpty, Double(raw) != nil else { throw ParseError(offset: start) }
            return .number(raw)
        }
    }

    // MARK: Writing

    /// Indented with two spaces, like `jq .`, ending with a newline.
    public func serialized() -> String {
        var out = ""
        write(to: &out, indent: 0)
        return out + "\n"
    }

    private func write(to out: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent + 1)
        let close = String(repeating: "  ", count: indent)
        switch self {
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{\n"
            for (n, (key, value)) in pairs.enumerated() {
                out += pad + Self.quote(key) + ": "
                value.write(to: &out, indent: indent + 1)
                out += n < pairs.count - 1 ? ",\n" : "\n"
            }
            out += close + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (n, item) in items.enumerated() {
                out += pad
                item.write(to: &out, indent: indent + 1)
                out += n < items.count - 1 ? ",\n" : "\n"
            }
            out += close + "]"
        case .string(let s): out += Self.quote(s)
        case .number(let raw): out += raw
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func quote(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes])) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

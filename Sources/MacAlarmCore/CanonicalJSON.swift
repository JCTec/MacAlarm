import Foundation

enum CanonicalJSON {
    static var encoder: JSONEncoder {
        makeEncoder()
    }

    static var decoder: JSONDecoder {
        makeDecoder()
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try encode(value)
        data.append(0x0A)
        return data
    }
}

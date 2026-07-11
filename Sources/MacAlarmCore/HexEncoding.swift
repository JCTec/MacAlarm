import Foundation

extension Data {
    init(hexEncoded string: String) throws {
        var bytes = [UInt8]()
        bytes.reserveCapacity(string.count / 2)

        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2, limitedBy: string.endIndex) ?? string.endIndex
            guard next <= string.endIndex else {
                throw MacAlarmError.invalidHexString
            }

            let byteString = String(string[index..<next])
            guard byteString.count == 2, let byte = UInt8(byteString, radix: 16) else {
                throw MacAlarmError.invalidHexString
            }

            bytes.append(byte)
            index = next
        }

        self = Data(bytes)
    }

    var hexEncodedString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

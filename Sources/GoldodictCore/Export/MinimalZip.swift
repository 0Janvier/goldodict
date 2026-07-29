import Foundation

/// Archive ZIP minimale, sans compression.
///
/// Le format ZIP admet des entrées « stored » (méthode 0) : pas de DEFLATE, donc
/// aucune dépendance ni framework — Word ouvre un .docx ainsi construit sans
/// sourciller, seule la taille y perd, ce qui est sans objet pour du texte.
public enum MinimalZip {

    public struct Entry: Sendable {
        public let path: String
        public let data: Data

        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    public static func archive(_ entries: [Entry]) -> Data {
        var output = Data()
        var central = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            offsets.append(UInt32(output.count))
            output.append(localHeader(for: entry))
            output.append(entry.data)
        }

        for (index, entry) in entries.enumerated() {
            central.append(centralRecord(for: entry, localOffset: offsets[index]))
        }

        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(endOfCentralDirectory(
            entryCount: UInt16(entries.count),
            centralSize: UInt32(central.count),
            centralOffset: centralOffset
        ))
        return output
    }

    // MARK: - Structures du format

    private static func localHeader(for entry: Entry) -> Data {
        let name = Data(entry.path.utf8)
        var data = Data()
        data.appendLE(UInt32(0x04034b50))          // signature
        data.appendLE(UInt16(20))                  // version requise
        data.appendLE(UInt16(0))                   // drapeaux
        data.appendLE(UInt16(0))                   // méthode 0 = stored
        data.appendLE(UInt16(0))                   // heure DOS
        data.appendLE(UInt16(0x21))                // date DOS (1er janvier 1980)
        data.appendLE(crc32(entry.data))
        data.appendLE(UInt32(entry.data.count))    // taille compressée
        data.appendLE(UInt32(entry.data.count))    // taille originale
        data.appendLE(UInt16(name.count))
        data.appendLE(UInt16(0))                   // extra
        data.append(name)
        return data
    }

    private static func centralRecord(for entry: Entry, localOffset: UInt32) -> Data {
        let name = Data(entry.path.utf8)
        var data = Data()
        data.appendLE(UInt32(0x02014b50))          // signature
        data.appendLE(UInt16(20))                  // version créatrice
        data.appendLE(UInt16(20))                  // version requise
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))                   // méthode 0
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0x21))
        data.appendLE(crc32(entry.data))
        data.appendLE(UInt32(entry.data.count))
        data.appendLE(UInt32(entry.data.count))
        data.appendLE(UInt16(name.count))
        data.appendLE(UInt16(0))                   // extra
        data.appendLE(UInt16(0))                   // commentaire
        data.appendLE(UInt16(0))                   // disque
        data.appendLE(UInt16(0))                   // attributs internes
        data.appendLE(UInt32(0))                   // attributs externes
        data.appendLE(localOffset)
        data.append(name)
        return data
    }

    private static func endOfCentralDirectory(
        entryCount: UInt16,
        centralSize: UInt32,
        centralOffset: UInt32
    ) -> Data {
        var data = Data()
        data.appendLE(UInt32(0x06054b50))          // signature EOCD
        data.appendLE(UInt16(0))                   // disque
        data.appendLE(UInt16(0))                   // disque du répertoire
        data.appendLE(entryCount)
        data.appendLE(entryCount)
        data.appendLE(centralSize)
        data.appendLE(centralOffset)
        data.appendLE(UInt16(0))                   // commentaire
        return data
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (value >> 1) ^ 0xEDB88320 : value >> 1
        }
        return value
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8(value >> 24))
    }
}

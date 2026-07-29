import Foundation
import Testing
@testable import GoldodictCore

@Suite("Archive ZIP minimale")
struct MinimalZipTests {

    @Test("Le CRC32 d'une chaîne connue est exact")
    func knownCRC() {
        // Valeur de référence publique pour "123456789".
        #expect(MinimalZip.crc32(Data("123456789".utf8)) == 0xCBF43926)
    }

    @Test("Les signatures du format sont présentes dans l'ordre")
    func signatures() {
        let archive = MinimalZip.archive([
            .init(path: "a.txt", data: Data("bonjour".utf8)),
        ])
        let bytes = [UInt8](archive)
        #expect(Array(bytes.prefix(4)) == [0x50, 0x4b, 0x03, 0x04])
        #expect(locate([0x50, 0x4b, 0x01, 0x02], in: bytes) != nil)
        #expect(locate([0x50, 0x4b, 0x05, 0x06], in: bytes) != nil)
    }

    @Test("Les noms et contenus survivent à une relecture")
    func roundTrip() throws {
        let entries: [MinimalZip.Entry] = [
            .init(path: "word/document.xml", data: Data("<w:document/>".utf8)),
            .init(path: "_rels/.rels", data: Data("<Relationships/>".utf8)),
        ]
        let archive = MinimalZip.archive(entries)
        let read = try readStoredZip(archive)
        #expect(read["word/document.xml"] == Data("<w:document/>".utf8))
        #expect(read["_rels/.rels"] == Data("<Relationships/>".utf8))
    }

    /// Mini-lecteur ZIP « stored » : suit les en-têtes locaux depuis le début.
    private func readStoredZip(_ data: Data) throws -> [String: Data] {
        var result: [String: Data] = [:]
        var offset = 0
        let bytes = [UInt8](data)

        while offset + 30 <= bytes.count,
              Array(bytes[offset..<offset + 4]) == [0x50, 0x4b, 0x03, 0x04] {
            let size = Int(le32(bytes, offset + 18))
            let nameLength = Int(le16(bytes, offset + 26))
            let extraLength = Int(le16(bytes, offset + 28))
            let nameStart = offset + 30
            let name = String(decoding: bytes[nameStart..<nameStart + nameLength], as: UTF8.self)
            let dataStart = nameStart + nameLength + extraLength
            result[name] = Data(bytes[dataStart..<dataStart + size])
            offset = dataStart + size
        }
        return result
    }

    private func le16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private func le32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
    }

    private func locate(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<start + needle.count]) == needle {
            return start
        }
        return nil
    }
}

@Suite("Export DOCX")
struct DocxExportTests {

    private var outline: DocumentOutline {
        var builder = DocumentOutlineBuilder()
        builder.append(DocumentOutlineParser.tokenize("titre un, sur la recevabilité"))
        builder.append(DocumentOutlineParser.tokenize("grand a, le délai de recours"))
        builder.append(DocumentOutlineParser.tokenize("citation le délai est de deux mois, fin de citation"))
        builder.append(DocumentOutlineParser.tokenize("la requête est donc recevable & fondée."))
        return builder.outline
    }

    @Test("Le document.xml porte les styles et les marqueurs littéraux")
    func documentContent() {
        let xml = DocxDocument.document(for: outline)
        #expect(xml.contains("Titre1"))
        #expect(xml.contains("Titre2"))
        #expect(xml.contains("Citation"))
        #expect(xml.contains("I. sur la recevabilité"))
        #expect(xml.contains("A. le délai de recours"))
    }

    @Test("Le texte dicté est échappé")
    func escaping() {
        let xml = DocxDocument.document(for: outline)
        #expect(xml.contains("recevable &amp; fondée."))
        #expect(!xml.contains("recevable & fondée."))
        #expect(DocxDocument.escape("a < b > \"c\"") == "a &lt; b &gt; &quot;c&quot;")
    }

    @Test("Le paquet complet contient toutes les parties et un XML bien formé")
    func packageComplete() throws {
        let parts = DocxDocument.parts(for: outline, title: "Consultation")
        let names = parts.map(\.path)
        #expect(names.contains("[Content_Types].xml"))
        #expect(names.contains("_rels/.rels"))
        #expect(names.contains("word/document.xml"))
        #expect(names.contains("word/styles.xml"))

        for part in parts {
            let parser = XMLParser(data: part.data)
            #expect(parser.parse(), "XML mal formé : \(part.path)")
        }

        let archive = DocxExporter.build(outline: outline, title: "Consultation")
        #expect(archive.count > 500)
        #expect(Array(archive.prefix(4)) == [0x50, 0x4b, 0x03, 0x04])
    }
}

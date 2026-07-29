import Foundation

/// Génère les parties XML d'un document Word à partir d'un plan dicté.
///
/// Les marqueurs de titres (« I. », « A. », « 1. ») sont écrits en toutes lettres
/// dans le paragraphe plutôt que confiés à la numérotation automatique de Word :
/// le document exporté est un premier jet destiné à être repris, et une
/// numérotation littérale survit à tous les copier-coller.
public enum DocxDocument {

    public static func parts(for outline: DocumentOutline, title: String) -> [MinimalZip.Entry] {
        [
            MinimalZip.Entry(path: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            MinimalZip.Entry(path: "_rels/.rels", data: Data(rootRelationships.utf8)),
            MinimalZip.Entry(path: "word/_rels/document.xml.rels", data: Data(documentRelationships.utf8)),
            MinimalZip.Entry(path: "docProps/core.xml", data: Data(coreProperties(title: title).utf8)),
            MinimalZip.Entry(path: "word/styles.xml", data: Data(styles.utf8)),
            MinimalZip.Entry(path: "word/document.xml", data: Data(document(for: outline).utf8)),
        ]
    }

    // MARK: - Contenu

    static func document(for outline: DocumentOutline) -> String {
        var body = ""
        for block in outline.preamble {
            body += paragraph(block)
        }
        for section in outline.sections {
            body += render(section)
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>\(body)<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>\
        <w:pgMar w:top="1417" w:right="1417" w:bottom="1417" w:left="1417"/></w:sectPr></w:body>
        </w:document>
        """
    }

    private static func render(_ node: OutlineNode) -> String {
        let style = "Titre\(min(max(node.level, 1), 3))"
        let text = node.heading.isEmpty ? node.marker : "\(node.marker) \(node.heading)"
        var result = """
        <w:p><w:pPr><w:pStyle w:val="\(style)"/></w:pPr>\(run(text))</w:p>
        """
        for block in node.blocks {
            result += paragraph(block)
        }
        for child in node.children {
            result += render(child)
        }
        return result
    }

    private static func paragraph(_ block: DocumentBlock) -> String {
        switch block {
        case .paragraph(let text):
            return "<w:p>\(run(text))</w:p>"
        case .quote(let text):
            return """
            <w:p><w:pPr><w:pStyle w:val="Citation"/></w:pPr>\(run("« \(text) »"))</w:p>
            """
        }
    }

    private static func run(_ text: String) -> String {
        "<w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r>"
    }

    static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Parties fixes

    /// Garamond 12 pt, français : la mise en page du cabinet.
    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
    <w:docDefaults><w:rPrDefault><w:rPr>\
    <w:rFonts w:ascii="Garamond" w:hAnsi="Garamond"/>\
    <w:sz w:val="24"/><w:lang w:val="fr-FR"/></w:rPr></w:rPrDefault>\
    <w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/>\
    <w:jc w:val="both"/></w:pPr></w:pPrDefault></w:docDefaults>
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
    <w:style w:type="paragraph" w:styleId="Titre1"><w:name w:val="Titre 1"/>\
    <w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="360" w:after="180"/>\
    <w:jc w:val="left"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Titre2"><w:name w:val="Titre 2"/>\
    <w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="240" w:after="120"/>\
    <w:ind w:left="284"/><w:jc w:val="left"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Titre3"><w:name w:val="Titre 3"/>\
    <w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="180" w:after="120"/>\
    <w:ind w:left="567"/><w:jc w:val="left"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>
    <w:style w:type="paragraph" w:styleId="Citation"><w:name w:val="Citation"/>\
    <w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="851" w:right="851"/></w:pPr>\
    <w:rPr><w:i/></w:rPr></w:style>
    </w:styles>
    """

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
    </Types>
    """

    private static let rootRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
    </Relationships>
    """

    private static let documentRelationships = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static func coreProperties(title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>\(escape(title))</dc:title>
        <dc:language>fr-FR</dc:language>
        </cp:coreProperties>
        """
    }
}

/// Assemblage final : les parties XML dans une archive ZIP.
public enum DocxExporter {
    public static func build(outline: DocumentOutline, title: String = "Document") -> Data {
        MinimalZip.archive(DocxDocument.parts(for: outline, title: title))
    }
}

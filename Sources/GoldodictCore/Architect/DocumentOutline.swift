import Foundation

/// Un bloc de contenu : paragraphe ordinaire ou citation en retrait.
public enum DocumentBlock: Codable, Equatable, Sendable {
    case paragraph(String)
    case quote(String)

    public var text: String {
        switch self {
        case .paragraph(let text), .quote(let text): return text
        }
    }
}

/// Un nœud du plan : marqueur (« I. », « A. », « 1. »), intitulé, blocs de
/// contenu et sous-parties.
public struct OutlineNode: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var level: Int
    public var marker: String
    public var heading: String
    public var blocks: [DocumentBlock]
    public var children: [OutlineNode]

    public init(
        id: UUID = UUID(),
        level: Int,
        marker: String,
        heading: String = "",
        blocks: [DocumentBlock] = [],
        children: [OutlineNode] = []
    ) {
        self.id = id
        self.level = level
        self.marker = marker
        self.heading = heading
        self.blocks = blocks
        self.children = children
    }
}

/// Le document en construction : un préambule (ce qui se dicte avant le premier
/// titre) puis l'arborescence des parties.
public struct DocumentOutline: Codable, Equatable, Sendable {
    public var preamble: [DocumentBlock]
    public var sections: [OutlineNode]

    public init(preamble: [DocumentBlock] = [], sections: [OutlineNode] = []) {
        self.preamble = preamble
        self.sections = sections
    }

    public var isEmpty: Bool { preamble.isEmpty && sections.isEmpty }
}

/// Construit le plan au fil des segments dictés.
///
/// Chaque segment (délimité par un silence) est tokenisé puis versé ici. Un
/// `.title` ouvre un nœud et met le reste du segment en capture d'intitulé ;
/// le segment suivant, sans nouveau titre, verse sa prose dans le nœud ouvert.
/// La prose se fond dans le dernier bloc de même nature — une pause de
/// respiration ne fragmente pas un paragraphe ; « nouvel alinéa » coupe.
public struct DocumentOutlineBuilder: Sendable {

    public private(set) var outline = DocumentOutline()

    /// Chemin (indices) du nœud ouvert, de la racine au plus profond.
    private var currentPath: [Int] = []
    private var inQuote = false
    private var breakRequested = false
    private var capturingHeading = false

    public init() {}

    public mutating func append(_ tokens: [DocumentToken]) {
        // La capture d'intitulé ne survit jamais au segment qui l'a ouverte.
        capturingHeading = false

        for token in tokens {
            switch token {
            case .command(.title(let level, let marker)):
                openNode(level: level, marker: marker)
                capturingHeading = true
                inQuote = false
                breakRequested = false

            case .command(.beginQuote):
                capturingHeading = false
                inQuote = true

            case .command(.endQuote):
                inQuote = false
                breakRequested = true

            case .command(.newParagraph):
                capturingHeading = false
                breakRequested = true

            case .prose(let text):
                if capturingHeading {
                    appendHeading(text)
                } else {
                    appendBlock(text)
                }
            }
        }
    }

    // MARK: - Nœuds

    private mutating func openNode(level: Int, marker: String) {
        // Remonte jusqu'au parent de niveau strictement inférieur. Un « grand A »
        // sans « titre » préalable s'attache à la racine : l'arbre le tolère, le
        // rendu lui donnera simplement son style de niveau.
        while let last = currentPath.count > 0 ? node(at: currentPath).level : nil, last >= level {
            currentPath.removeLast()
        }
        let child = OutlineNode(level: level, marker: marker)
        if currentPath.isEmpty {
            outline.sections.append(child)
            currentPath = [outline.sections.count - 1]
        } else {
            appendChild(child, at: currentPath)
            currentPath.append(node(at: currentPath).children.count - 1)
        }
    }

    private mutating func appendHeading(_ text: String) {
        guard !currentPath.isEmpty else { return }
        modifyNode(at: currentPath) { node in
            node.heading = node.heading.isEmpty ? text : node.heading + " " + text
        }
    }

    private mutating func appendBlock(_ text: String) {
        let quoted = inQuote
        let forceBreak = breakRequested
        breakRequested = false

        if currentPath.isEmpty {
            Self.merge(text, quoted: quoted, forceBreak: forceBreak, into: &outline.preamble)
        } else {
            modifyNode(at: currentPath) { node in
                Self.merge(text, quoted: quoted, forceBreak: forceBreak, into: &node.blocks)
            }
        }
    }

    private static func merge(
        _ text: String,
        quoted: Bool,
        forceBreak: Bool,
        into blocks: inout [DocumentBlock]
    ) {
        if !forceBreak, let last = blocks.last {
            switch (last, quoted) {
            case (.paragraph(let existing), false):
                blocks[blocks.count - 1] = .paragraph(existing + " " + text)
                return
            case (.quote(let existing), true):
                blocks[blocks.count - 1] = .quote(existing + " " + text)
                return
            default:
                break
            }
        }
        blocks.append(quoted ? .quote(text) : .paragraph(text))
    }

    // MARK: - Accès par chemin

    private func node(at path: [Int]) -> OutlineNode {
        var current = outline.sections[path[0]]
        for index in path.dropFirst() {
            current = current.children[index]
        }
        return current
    }

    private mutating func modifyNode(at path: [Int], _ change: (inout OutlineNode) -> Void) {
        modify(&outline.sections, path: path[...], change)
    }

    private mutating func appendChild(_ child: OutlineNode, at path: [Int]) {
        modify(&outline.sections, path: path[...]) { $0.children.append(child) }
    }

    private func modify(
        _ nodes: inout [OutlineNode],
        path: ArraySlice<Int>,
        _ change: (inout OutlineNode) -> Void
    ) {
        guard let head = path.first else { return }
        if path.count == 1 {
            change(&nodes[head])
        } else {
            modify(&nodes[head].children, path: path.dropFirst(), change)
        }
    }
}

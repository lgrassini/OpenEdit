import Foundation

struct DocumentModel {
    var blocks: [Block] = []
}

enum Block {
    case paragraph(Paragraph)
    case heading(Heading)
    case list(ODTList)
    case image(ImageBlock)
    case horizontalRule
}

struct Paragraph {
    var runs: [Run]
    var styleName: String
    init(runs: [Run] = [], styleName: String = "") {
        self.runs = runs; self.styleName = styleName
    }
    var plainText: String { runs.map(\.text).joined() }
}

struct Heading {
    var level: Int       // 1–4
    var runs: [Run]
    var styleName: String
    init(level: Int, runs: [Run] = [], styleName: String = "") {
        self.level = max(1, min(4, level)); self.runs = runs; self.styleName = styleName
    }
    var plainText: String { runs.map(\.text).joined() }
}

struct ODTList {
    var styleName: String
    var items: [ListItem]
    init(styleName: String = "", items: [ListItem] = []) {
        self.styleName = styleName; self.items = items
    }
}

struct ListItem {
    var runs: [Run]
    var sublist: ODTList?
    init(runs: [Run] = [], sublist: ODTList? = nil) {
        self.runs = runs; self.sublist = sublist
    }
    var plainText: String { runs.map(\.text).joined() }
}

struct ImageBlock {
    var href: String      // e.g. "Pictures/image1.png"
    var width: Double     // cm
    var height: Double    // cm
}

struct Run {
    var text: String
    var props: TextProperties
    init(text: String, props: TextProperties = .plain) {
        self.text = text; self.props = props
    }
}

struct TextProperties: Equatable, Hashable {
    var bold: Bool?
    var italic: Bool?
    var strikethrough: Bool?
    var fontName: String?
    var fontSize: Double?    // points
    var color: String?       // "#RRGGBB"
    var href: String?        // hyperlink URL (maps to text:a xlink:href)

    static let plain = TextProperties()

    var isBold: Bool          { bold          ?? false }
    var isItalic: Bool        { italic        ?? false }
    var isStrikethrough: Bool { strikethrough ?? false }

    /// Returns self with non-nil values from `child` taking precedence.
    func merging(_ child: TextProperties) -> TextProperties {
        TextProperties(
            bold:          child.bold          ?? bold,
            italic:        child.italic        ?? italic,
            strikethrough: child.strikethrough ?? strikethrough,
            fontName:      child.fontName      ?? fontName,
            fontSize:      child.fontSize      ?? fontSize,
            color:         child.color         ?? color,
            href:          child.href          ?? href
        )
    }
}

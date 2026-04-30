import Foundation

final class ODTParser {

    // Automatic character style name → text properties
    private var charStyles: [String: TextProperties] = [:]

    func parse(_ package: ODTPackage) throws -> DocumentModel {
        let xmlDoc = try XMLDocument(data: package.contentXML, options: [])
        guard let root = xmlDoc.rootElement() else { return DocumentModel() }

        if let autoStylesEl = root.firstChild(localName: "automatic-styles") {
            parseAutomaticStyles(autoStylesEl)
        }

        guard let bodyEl = root.firstChild(localName: "body"),
              let textEl = bodyEl.firstChild(localName: "text") else {
            return DocumentModel()
        }

        return DocumentModel(blocks: parseBody(textEl))
    }

    // MARK: - Automatic styles

    private func parseAutomaticStyles(_ el: XMLElement) {
        for styleEl in el.childElements where styleEl.localName == "style" {
            guard let name   = styleEl.attr("style:name"),
                  let family = styleEl.attr("style:family"),
                  family == "text" else { continue }
            charStyles[name] = extractTextProps(styleEl)
        }
    }

    private func extractTextProps(_ styleEl: XMLElement) -> TextProperties {
        guard let tp = styleEl.firstChild(localName: "text-properties") else { return .plain }
        var props = TextProperties()

        if let fw = tp.attr("fo:font-weight") {
            props.bold = fw == "bold" || (Int(fw).map { $0 > 400 } ?? false)
        }
        if let fs = tp.attr("fo:font-style") {
            props.italic = fs == "italic" || fs == "oblique"
        }
        if let lt = tp.attr("style:text-line-through-style") {
            props.strikethrough = lt != "none" && !lt.isEmpty
        }
        if let fn = tp.attr("style:font-name") ?? tp.attr("fo:font-family") {
            props.fontName = fn.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }
        if let fz = tp.attr("fo:font-size") {
            props.fontSize = parsePoints(fz)
        }
        if let c = tp.attr("fo:color"), c.hasPrefix("#") {
            props.color = c
        }
        return props
    }

    // MARK: - Body blocks

    private func parseBody(_ textEl: XMLElement) -> [Block] {
        var blocks: [Block] = []
        for child in textEl.childElements {
            switch child.localName {
            case "p":
                blocks.append(.paragraph(Paragraph(
                    runs: parseRuns(child),
                    styleName: child.attr("text:style-name") ?? ""
                )))
            case "h":
                let level = Int(child.attr("text:outline-level") ?? "1") ?? 1
                blocks.append(.heading(Heading(
                    level: level,
                    runs: parseRuns(child),
                    styleName: child.attr("text:style-name") ?? ""
                )))
            case "list":
                blocks.append(.list(parseList(child)))
            default:
                break
            }
        }
        return blocks
    }

    // MARK: - Runs

    private func parseRuns(_ el: XMLElement,
                            inheritedProps: TextProperties = .plain) -> [Run] {
        var runs: [Run] = []
        for node in el.children ?? [] {
            if let child = node as? XMLElement {
                switch child.localName {
                case "span":
                    let spanProps = charStyles[child.attr("text:style-name") ?? ""] ?? .plain
                    runs += parseRuns(child, inheritedProps: inheritedProps.merging(spanProps))
                case "s":
                    let n = Int(child.attr("text:c") ?? "1") ?? 1
                    runs.append(Run(text: String(repeating: " ", count: max(1, n)),
                                    props: inheritedProps))
                case "tab":
                    runs.append(Run(text: "\t", props: inheritedProps))
                case "line-break":
                    runs.append(Run(text: "\n", props: inheritedProps))
                default:
                    break
                }
            } else if node.kind == .text {
                let str = node.stringValue ?? ""
                if !str.isEmpty {
                    runs.append(Run(text: str, props: inheritedProps))
                }
            }
        }
        return runs
    }

    // MARK: - Lists

    private func parseList(_ el: XMLElement) -> ODTList {
        let styleName = el.attr("text:style-name") ?? ""
        var items: [ListItem] = []
        for itemEl in el.childElements where itemEl.localName == "list-item" {
            var runs: [Run] = []
            var sublist: ODTList? = nil
            for child in itemEl.childElements {
                switch child.localName {
                case "p", "h": runs += parseRuns(child)
                case "list":   sublist = parseList(child)
                default: break
                }
            }
            items.append(ListItem(runs: runs, sublist: sublist))
        }
        return ODTList(styleName: styleName, items: items)
    }

    // MARK: - Helpers

    private func parsePoints(_ str: String) -> Double? {
        if str.hasSuffix("pt") { return Double(str.dropLast(2)) }
        if str.hasSuffix("cm") { return Double(str.dropLast(2)).map { $0 * 28.3465 } }
        return Double(str)
    }
}

// MARK: - XMLElement helpers

private extension XMLElement {
    var childElements: [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }
    }
    func firstChild(localName name: String) -> XMLElement? {
        childElements.first { $0.localName == name }
    }
    func attr(_ qualifiedName: String) -> String? {
        attribute(forName: qualifiedName)?.stringValue
    }
}

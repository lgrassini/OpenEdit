import AppKit

struct ModelExtractor {

    func extract(from storage: NSTextStorage) -> DocumentModel {
        let paras = splitParagraphs(storage)
        var blocks: [Block] = []
        var i = 0
        while i < paras.count {
            let (range, code) = paras[i]
            switch code {
            case 0:
                let runs = extractRuns(from: storage, in: range,
                                       isListItem: false, blockCode: 0)
                blocks.append(.paragraph(Paragraph(runs: runs)))
                i += 1
            case 1...4:
                let runs = extractRuns(from: storage, in: range,
                                       isListItem: false, blockCode: code)
                blocks.append(.heading(Heading(level: code, runs: runs)))
                i += 1
            default: // >= 10 → list items
                let (list, consumed) = extractList(from: storage,
                                                   paras: paras,
                                                   start: i,
                                                   depth: 0)
                blocks.append(.list(list))
                i += consumed
            }
        }
        return DocumentModel(blocks: blocks.isEmpty
            ? [.paragraph(Paragraph())]
            : blocks)
    }

    // MARK: - Paragraph splitting

    /// Returns (contentRange, blockCode) for every paragraph in the storage.
    /// contentRange excludes the trailing newline.
    private func splitParagraphs(_ storage: NSTextStorage) -> [(NSRange, Int)] {
        let str = storage.string as NSString
        var result: [(NSRange, Int)] = []
        var pos = 0
        let len = str.length
        while pos < len {
            let pr = str.paragraphRange(for: NSRange(location: pos, length: 0))
            guard pr.length > 0 else { break }

            let hasNL = str.character(at: NSMaxRange(pr) - 1) == 10  // '\n'
            let contentRange = NSRange(location: pr.location,
                                       length: pr.length - (hasNL ? 1 : 0))

            let code = (storage.attribute(.odtBlockType,
                                          at: pr.location,
                                          effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            result.append((contentRange, code))
            pos = NSMaxRange(pr)
        }
        return result
    }

    // MARK: - List extraction

    private func extractList(from storage: NSTextStorage,
                              paras: [(NSRange, Int)],
                              start: Int,
                              depth: Int) -> (ODTList, Int) {
        var items: [ListItem] = []
        var i = start

        while i < paras.count {
            let (range, code) = paras[i]
            guard code >= 10 else { break }          // not a list item
            let itemDepth = code - 10
            guard itemDepth >= depth else { break }  // back to shallower level

            if itemDepth == depth {
                i += 1
                var sublist: ODTList? = nil
                if i < paras.count, paras[i].1 >= 10, paras[i].1 - 10 > depth {
                    let (sub, n) = extractList(from: storage,
                                               paras: paras,
                                               start: i,
                                               depth: depth + 1)
                    sublist = sub
                    i += n
                }
                let runs = extractRuns(from: storage, in: range,
                                       isListItem: true, blockCode: code)
                items.append(ListItem(runs: runs, sublist: sublist))
            } else {
                // Deeper orphan — shouldn't happen; stop to avoid infinite loop
                break
            }
        }
        return (ODTList(items: items), i - start)
    }

    // MARK: - Run extraction

    private func extractRuns(from storage: NSTextStorage,
                              in range: NSRange,
                              isListItem: Bool,
                              blockCode: Int) -> [Run] {
        guard range.length > 0 else { return [] }

        // Find where the actual content starts (skip the bullet marker).
        var contentStart = range.location
        if isListItem {
            storage.enumerateAttribute(.odtListMarker,
                                       in: range,
                                       options: []) { val, r, stop in
                if (val as? NSNumber)?.intValue == 1 {
                    contentStart = NSMaxRange(r)
                } else {
                    stop.pointee = true
                }
            }
        }

        let contentRange = NSRange(location: contentStart,
                                   length: NSMaxRange(range) - contentStart)
        guard contentRange.length > 0 else { return [] }

        let str = storage.string as NSString
        var runs: [Run] = []

        storage.enumerateAttributes(in: contentRange, options: []) { attrs, r, _ in
            // Skip any stray marker characters
            if (attrs[.odtListMarker] as? NSNumber)?.intValue == 1 { return }
            let text = str.substring(with: r)
            guard !text.isEmpty else { return }
            runs.append(Run(text: text, props: textProps(from: attrs, blockCode: blockCode)))
        }

        return coalesce(runs)
    }

    // MARK: - TextProperties extraction

    /// Extracts only *explicit* overrides relative to the block's natural styling.
    private func textProps(from attrs: [NSAttributedString.Key: Any],
                            blockCode: Int) -> TextProperties {
        var props = TextProperties()
        let natural = naturalFont(for: blockCode)

        if let font = attrs[.font] as? NSFont {
            let traits  = font.fontDescriptor.symbolicTraits
            let nTraits = natural.fontDescriptor.symbolicTraits

            // Bold/italic: only record if different from the block's natural state.
            if traits.contains(.bold)   != nTraits.contains(.bold)   { props.bold   = traits.contains(.bold) }
            if traits.contains(.italic) != nTraits.contains(.italic) { props.italic = traits.contains(.italic) }

            // Family: only record if it departs from the system font.
            let systemFamily = NSFont.systemFont(ofSize: 12).familyName ?? ""
            if let family = font.familyName, family != systemFamily {
                props.fontName = family
            }

            // Size: only record if it departs from the natural block size.
            if abs(font.pointSize - natural.pointSize) > 0.1 {
                props.fontSize = Double(font.pointSize)
            }
        }

        if let st = attrs[.strikethroughStyle] as? Int, st != 0 {
            props.strikethrough = true
        }

        if let color = attrs[.foregroundColor] as? NSColor,
           !color.isEqual(NSColor.labelColor) {
            props.color = color.odtHex
        }

        return props
    }

    /// The font that ModelRenderer uses for a block with no run overrides.
    private func naturalFont(for blockCode: Int) -> NSFont {
        switch blockCode {
        case 1: return NSFont.boldSystemFont(ofSize: 20)
        case 2: return NSFont.boldSystemFont(ofSize: 17)
        case 3: return NSFont.boldSystemFont(ofSize: 14)
        case 4: return NSFont.boldSystemFont(ofSize: 12)
        default: return NSFont.systemFont(ofSize: 12) // paragraph + list items
        }
    }

    // MARK: - Coalescing

    private func coalesce(_ runs: [Run]) -> [Run] {
        var out: [Run] = []
        for r in runs {
            if !out.isEmpty, out[out.count - 1].props == r.props {
                out[out.count - 1].text += r.text
            } else {
                out.append(r)
            }
        }
        return out
    }
}

// MARK: - NSColor → hex (file-private)

private extension NSColor {
    var odtHex: String? {
        guard let c = usingColorSpace(.genericRGB) else { return nil }
        let r = Int((c.redComponent   * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent  * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

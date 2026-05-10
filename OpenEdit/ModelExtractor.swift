import AppKit

struct ModelExtractor {

    func extract(from storage: NSTextStorage) -> DocumentModel {
        let paras = splitParagraphs(storage)
        var blocks: [Block] = []
        var i = 0
        while i < paras.count {
            let (range, code) = paras[i]
            switch code {

            case -2: // horizontal rule attachment
                blocks.append(.horizontalRule)
                i += 1

            case -1: // image attachment
                if let img = extractImage(from: storage, at: range.location) {
                    blocks.append(.image(img))
                }
                i += 1

            case 0: // paragraph
                blocks.append(.paragraph(Paragraph(
                    runs: extractRuns(from: storage, in: range,
                                      isListItem: false, blockCode: 0))))
                i += 1

            case 5: // monospaced paragraph
                blocks.append(.paragraph(Paragraph(
                    runs: extractRuns(from: storage, in: range,
                                      isListItem: false, blockCode: 5),
                    styleName: "Preformatted_20_Text")))
                i += 1

            case 1...4: // heading
                blocks.append(.heading(Heading(
                    level: code,
                    runs: extractRuns(from: storage, in: range,
                                      isListItem: false, blockCode: code))))
                i += 1

            case 10...: // list items
                let (list, consumed) = extractList(from: storage,
                                                   paras: paras,
                                                   start: i,
                                                   depth: 0)
                blocks.append(.list(list))
                i += consumed

            default:
                i += 1
            }
        }
        return DocumentModel(blocks: blocks.isEmpty ? [.paragraph(Paragraph())] : blocks)
    }

    // MARK: - Paragraph splitting

    private func splitParagraphs(_ storage: NSTextStorage) -> [(NSRange, Int)] {
        let str = storage.string as NSString
        var result: [(NSRange, Int)] = []
        var pos = 0
        let len = str.length
        while pos < len {
            let pr = str.paragraphRange(for: NSRange(location: pos, length: 0))
            guard pr.length > 0 else { break }
            let hasNL = str.character(at: NSMaxRange(pr) - 1) == 10
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

    // MARK: - Image extraction

    private func extractImage(from storage: NSTextStorage, at location: Int) -> ImageBlock? {
        guard location < storage.length else { return nil }
        let href = (storage.attribute(.odtImageHref,
                                      at: location,
                                      effectiveRange: nil) as? String) ?? ""
        guard let attachment = storage.attribute(.attachment,
                                                  at: location,
                                                  effectiveRange: nil) as? NSTextAttachment
        else { return nil }

        let ptsToCm = 2.54 / 72.0
        let bounds  = attachment.bounds
        let imgSize = attachment.image?.size ?? NSSize(width: 200, height: 150)
        let w = Double(bounds.width  > 0 ? bounds.width  : imgSize.width)  * ptsToCm
        let h = Double(bounds.height > 0 ? bounds.height : imgSize.height) * ptsToCm
        return ImageBlock(href: href, width: w, height: h)
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
            guard code >= 10 else { break }
            let itemDepth = code - 10
            guard itemDepth >= depth else { break }

            if itemDepth == depth {
                i += 1
                var sublist: ODTList? = nil
                if i < paras.count, paras[i].1 >= 10, paras[i].1 - 10 > depth {
                    let (sub, n) = extractList(from: storage, paras: paras,
                                               start: i, depth: depth + 1)
                    sublist = sub
                    i += n
                }
                items.append(ListItem(
                    runs: extractRuns(from: storage, in: range,
                                      isListItem: true, blockCode: code),
                    sublist: sublist))
            } else {
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

        var contentStart = range.location
        if isListItem {
            storage.enumerateAttribute(.odtListMarker, in: range, options: []) { val, r, stop in
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

        let str  = storage.string as NSString
        var runs: [Run] = []

        storage.enumerateAttributes(in: contentRange, options: []) { attrs, r, _ in
            if (attrs[.odtListMarker] as? NSNumber)?.intValue == 1 { return }
            let text = str.substring(with: r)
            guard !text.isEmpty else { return }
            runs.append(Run(text: text, props: textProps(from: attrs, blockCode: blockCode)))
        }
        return coalesce(runs)
    }

    // MARK: - TextProperties extraction

    private func textProps(from attrs: [NSAttributedString.Key: Any],
                            blockCode: Int) -> TextProperties {
        var props = TextProperties()
        let natural = naturalFont(for: blockCode)

        if let font = attrs[.font] as? NSFont {
            let traits  = font.fontDescriptor.symbolicTraits
            let nTraits = natural.fontDescriptor.symbolicTraits
            if traits.contains(.bold)   != nTraits.contains(.bold)   { props.bold   = traits.contains(.bold) }
            if traits.contains(.italic) != nTraits.contains(.italic) { props.italic = traits.contains(.italic) }

            let naturalFamily = natural.familyName ?? ""
            if let family = font.familyName, family != naturalFamily { props.fontName = family }
            if abs(font.pointSize - natural.pointSize) > 0.1 { props.fontSize = Double(font.pointSize) }
        }

        if let st = attrs[.strikethroughStyle] as? Int, st != 0 { props.strikethrough = true }

        if let color = attrs[.foregroundColor] as? NSColor, !color.isEqual(NSColor.labelColor) {
            props.color = color.odtHex
        }
        return props
    }

    private func naturalFont(for blockCode: Int) -> NSFont { ModelRenderer.font(for: blockCode) }

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

// MARK: - NSColor → hex

private extension NSColor {
    var odtHex: String? {
        guard let c = usingColorSpace(.genericRGB) else { return nil }
        let r = Int((c.redComponent   * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent  * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

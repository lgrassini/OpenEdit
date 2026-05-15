import AppKit

// MARK: - Custom attribute keys

extension NSAttributedString.Key {
    /// Block-type tag stored as NSNumber:
    ///   -2    = horizontal rule
    ///   -1    = image block
    ///    0    = paragraph
    ///    1–4  = heading at that outline level
    ///    5    = monospaced paragraph
    ///   10    = list item, depth 0 (top-level)
    ///   11    = list item, depth 1
    ///   12    = list item, depth 2
    static let odtBlockType  = NSAttributedString.Key("dev.openedit.blockType")

    /// NSNumber(1) marks the bullet/marker prefix of a list item (non-content).
    static let odtListMarker = NSAttributedString.Key("dev.openedit.listMarker")

    /// String: the Pictures/ href of an embedded image attachment.
    static let odtImageHref  = NSAttributedString.Key("dev.openedit.imageHref")
}

// MARK: - Shared style look-up (used by renderer AND toolbar)

extension ModelRenderer {

    /// Canonical font for a given block code (0 = paragraph, 1–4 = heading level, 5 = monospaced).
    static func font(for code: Int) -> NSFont {
        switch code {
        case 1: return .boldSystemFont(ofSize: 20)
        case 2: return .boldSystemFont(ofSize: 17)
        case 3: return .boldSystemFont(ofSize: 14)
        case 4: return .boldSystemFont(ofSize: 12)
        case 5: return .monospacedSystemFont(ofSize: 12, weight: .regular)
        default: return .systemFont(ofSize: 12)
        }
    }

    /// Canonical paragraph style for a given block code.
    static func paragraphStyle(for code: Int) -> NSParagraphStyle {
        let s = NSMutableParagraphStyle()
        switch code {
        case 1, 2: s.paragraphSpacingBefore = 8; s.lineSpacing = 2
        case 3, 4: s.paragraphSpacingBefore = 4; s.lineSpacing = 2
        default:   s.lineSpacing = 2
        }
        return s
    }

    /// Canonical paragraph style for a list item at the given depth.
    static func listParagraphStyle(for depth: Int) -> NSParagraphStyle {
        let indent = CGFloat(depth + 1) * 18
        let s = NSMutableParagraphStyle()
        s.firstLineHeadIndent = indent
        s.headIndent = indent + 16
        return s
    }
}

// MARK: - Renderer

struct ModelRenderer {

    /// Render a DocumentModel into an NSAttributedString for display in NSTextView.
    /// Pass the package's pictures dictionary so embedded images are resolved.
    func render(_ model: DocumentModel,
                pictures: [String: Data] = [:]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let blocks = model.blocks.isEmpty ? [Block.paragraph(Paragraph())] : model.blocks
        var first = true
        for block in blocks {
            if !first { out.append(nl) }
            first = false
            out.append(renderBlock(block, pictures: pictures))
        }
        return out
    }

    // MARK: Blocks

    private var nl: NSAttributedString { NSAttributedString(string: "\n") }

    private func renderBlock(_ block: Block, pictures: [String: Data]) -> NSAttributedString {
        switch block {
        case .paragraph(let p):  return renderParagraph(p)
        case .heading(let h):    return renderHeading(h)
        case .list(let l):       return renderListItems(l, depth: 0)
        case .image(let img):    return renderImage(img, pictures: pictures)
        case .horizontalRule:    return ModelRenderer.horizontalRuleAttachment()
        }
    }

    private static let monospacedStyleNames: Set<String> = [
        "Preformatted_20_Text", "Preformatted Text"
    ]

    private func renderParagraph(_ p: Paragraph) -> NSAttributedString {
        let isMonospaced = Self.monospacedStyleNames.contains(p.styleName)
        let code = isMonospaced ? 5 : 0
        let font = ModelRenderer.font(for: code)
        let base = blockAttrs(code: code, font: font, ps: ModelRenderer.paragraphStyle(for: 0))
        return applyRuns(p.runs, base: base, baseFont: font)
    }

    private func renderHeading(_ h: Heading) -> NSAttributedString {
        let font = ModelRenderer.font(for: h.level)
        let base = blockAttrs(code: h.level, font: font,
                              ps: ModelRenderer.paragraphStyle(for: h.level))
        return applyRuns(h.runs, base: base, baseFont: font)
    }

    private func renderListItems(_ list: ODTList, depth: Int) -> NSAttributedString {
        let out    = NSMutableAttributedString()
        let font   = ModelRenderer.font(for: 0)
        let code   = 10 + depth
        let ps     = ModelRenderer.listParagraphStyle(for: depth)
        let bullets = ["• ", "◦ ", "▪ "]
        let bullet  = depth < bullets.count ? bullets[depth] : "▪ "

        var first = true
        for item in list.items {
            if !first { out.append(nl) }
            first = false

            let base = blockAttrs(code: code, font: font, ps: ps)

            var markerAttrs = base
            markerAttrs[.odtListMarker] = NSNumber(value: 1)
            out.append(NSAttributedString(string: bullet, attributes: markerAttrs))
            out.append(applyRuns(item.runs, base: base, baseFont: font))

            if let sub = item.sublist {
                out.append(nl)
                out.append(renderListItems(sub, depth: depth + 1))
            }
        }
        return out
    }

    private func renderImage(_ img: ImageBlock, pictures: [String: Data]) -> NSAttributedString {
        guard let data = pictures[img.href],
              let nsImage = NSImage(data: data) else {
            // Placeholder when image data is unavailable
            let s = NSMutableParagraphStyle(); s.alignment = .center
            return NSAttributedString(
                string: "[\(URL(fileURLWithPath: img.href).lastPathComponent)]",
                attributes: [.odtBlockType: NSNumber(value: -1),
                             .paragraphStyle: s])
        }
        let maxWidth: CGFloat = 440
        let scale = min(1.0, maxWidth / nsImage.size.width)
        let size  = NSSize(width:  nsImage.size.width  * scale,
                           height: nsImage.size.height * scale)

        let attachment        = NSTextAttachment()
        attachment.image      = nsImage
        attachment.bounds     = NSRect(origin: .zero, size: size)

        let str = NSMutableAttributedString(attachment: attachment)
        str.addAttributes([.odtBlockType: NSNumber(value: -1),
                           .odtImageHref: img.href],
                          range: NSRange(location: 0, length: 1))
        return str
    }

    // MARK: Runs

    private func applyRuns(_ runs: [Run],
                            base: [NSAttributedString.Key: Any],
                            baseFont: NSFont) -> NSAttributedString {
        if runs.isEmpty { return NSAttributedString(string: "", attributes: base) }
        let out = NSMutableAttributedString()
        for run in runs {
            var a = base
            a[.font] = resolvedFont(run.props, baseFont: baseFont)
            a[.strikethroughStyle] = run.props.isStrikethrough
                ? NSUnderlineStyle.single.rawValue : 0
            if let hex = run.props.color, let c = NSColor(odtHex: hex) {
                a[.foregroundColor] = c
            }
            // .link is a standard NSAttributedString key; NSTextView applies link
            // colour, underline, and pointing-hand cursor automatically via
            // linkTextAttributes (temporary attributes — they never land in storage).
            if let href = run.props.href {
                a[.link] = URL(string: href) ?? href
            }
            out.append(NSAttributedString(string: run.text, attributes: a))
        }
        return out
    }

    // MARK: Font helpers

    private func resolvedFont(_ props: TextProperties, baseFont: NSFont) -> NSFont {
        let size = props.fontSize.map { CGFloat($0) } ?? baseFont.pointSize
        let desc: NSFontDescriptor = props.fontName != nil
            ? NSFontDescriptor(name: props.fontName!, size: size)
            : baseFont.fontDescriptor.withSize(size)

        var traits = desc.symbolicTraits
        if let b = props.bold   { if b { traits.insert(.bold)   } else { traits.remove(.bold) } }
        if let i = props.italic { if i { traits.insert(.italic) } else { traits.remove(.italic) } }
        let updated = desc.withSymbolicTraits(traits)
        return NSFont(descriptor: updated, size: size)
            ?? NSFont(descriptor: desc,    size: size)
            ?? baseFont
    }

    // MARK: Helpers

    private func blockAttrs(code: Int,
                             font: NSFont,
                             ps: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .odtBlockType:    NSNumber(value: code),
            .font:            font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle:  ps
        ]
    }
}

// MARK: - Horizontal rule attachment

extension ModelRenderer {
    /// Creates the attributed string used both when rendering from a model and when
    /// inserting a new horizontal rule from the menu.
    static func horizontalRuleAttachment() -> NSAttributedString {
        let width:  CGFloat = 500
        let height: CGFloat = 14
        let ruleImage = NSImage(size: NSSize(width: width, height: height),
                                flipped: false) { dstRect in
            NSColor.separatorColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 0.5
            let mid = dstRect.height * 0.5
            path.move(to: NSPoint(x: dstRect.minX, y: mid))
            path.line(to: NSPoint(x: dstRect.maxX, y: mid))
            path.stroke()
            return true
        }
        let attachment = NSTextAttachment()
        attachment.image = ruleImage
        attachment.bounds = NSRect(x: 0, y: -4, width: width, height: height)
        let str = NSMutableAttributedString(attachment: attachment)
        str.addAttribute(.odtBlockType, value: NSNumber(value: -2),
                         range: NSRange(location: 0, length: 1))
        return str
    }
}

// MARK: - NSColor hex init

extension NSColor {
    convenience init?(odtHex hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red:   CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >>  8) & 0xFF) / 255,
                  blue:  CGFloat( v        & 0xFF) / 255,
                  alpha: 1)
    }
}

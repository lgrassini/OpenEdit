import AppKit
import UniformTypeIdentifiers

// MARK: - Toolbar item identifiers

private extension NSToolbarItem.Identifier {
    static let bold           = NSToolbarItem.Identifier("bold")
    static let italic         = NSToolbarItem.Identifier("italic")
    static let strikethrough  = NSToolbarItem.Identifier("strikethrough")
    static let bullets        = NSToolbarItem.Identifier("bullets")
    static let increaseIndent = NSToolbarItem.Identifier("increaseIndent")
    static let decreaseIndent = NSToolbarItem.Identifier("decreaseIndent")
    static let insertImage    = NSToolbarItem.Identifier("insertImage")
}

// MARK: - EditorViewController

final class EditorViewController: NSViewController {

    // MARK: Text view

    private(set) var textView: NSTextView!
    weak var odtDocument: ODTDocument?
    private var hasLoaded = false
    private var isAutoDetecting = false

    // MARK: Toolbar controls

    private var boldButton:    NSButton?
    private var italicButton:  NSButton?
    private var strikeButton:  NSButton?
    private var bulletsButton: NSButton?

    // MARK: - View setup

    override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 860, height: 640))
        scrollView.borderType            = .noBorder
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers    = true
        scrollView.backgroundColor       = .textBackgroundColor

        let contentSize = scrollView.contentSize
        let tv = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        tv.minSize                    = NSSize(width: 0, height: contentSize.height)
        tv.maxSize                    = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                               height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable      = true
        tv.isHorizontallyResizable    = false
        tv.autoresizingMask           = .width
        tv.textContainer?.containerSize = NSSize(width: contentSize.width,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset         = NSSize(width: 60, height: 48)

        tv.isRichText                 = true
        tv.isEditable                 = true
        tv.isSelectable               = true
        tv.allowsUndo                 = true
        tv.usesFindPanel              = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled  = false
        tv.backgroundColor            = .textBackgroundColor
        tv.textColor                  = .labelColor
        tv.delegate                   = self

        scrollView.documentView = tv
        textView = tv
        view = scrollView
    }

    // MARK: - Lifecycle

    override func viewWillAppear() {
        super.viewWillAppear()
        if !hasLoaded {
            hasLoaded = true
            loadFromDocument()
            setUpToolbar()
        }
        view.window?.makeFirstResponder(textView)
    }

    // MARK: - Load / Extract

    func loadFromDocument() {
        guard let doc = odtDocument else { return }
        let attrStr = ModelRenderer().render(doc.model, pictures: doc.package.pictures)
        textView.textStorage?.setAttributedString(attrStr)
        updateToolbarState()
    }

    func currentModel() -> DocumentModel {
        guard let storage = textView.textStorage else { return DocumentModel() }
        return ModelExtractor().extract(from: storage)
    }

    // MARK: - Toolbar setup

    private func setUpToolbar() {
        guard let window = view.window, window.toolbar == nil else { return }
        let tb = NSToolbar(identifier: "OpenEditToolbar")
        tb.delegate               = self
        tb.displayMode            = .iconOnly
        tb.allowsUserCustomization = false
        window.toolbar = tb
    }

    // MARK: - Block style

    func applyBlockType(_ code: Int) {
        guard let storage = textView.textStorage else { return }
        let font = ModelRenderer.font(for: code)
        let ps   = ModelRenderer.paragraphStyle(for: code)
        storage.beginEditing()
        enumerateParagraphs(in: textView.selectedRange(), storage: storage) { pr in
            let existing = (storage.attribute(.odtBlockType, at: pr.location,
                                              effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            guard existing != -1 else { return } // skip image blocks
            storage.addAttribute(.odtBlockType,   value: NSNumber(value: code), range: pr)
            storage.addAttribute(.font,           value: font,                  range: pr)
            storage.addAttribute(.paragraphStyle, value: ps,                    range: pr)
        }
        storage.endEditing()
        textView.didChangeText()
        odtDocument?.markAsEdited()
    }

    // MARK: - Inline formatting

    @objc func toggleBold(_ sender: NSButton) {
        applyTrait(.bold, isOn: sender.state == .on)
    }

    @objc func toggleItalic(_ sender: NSButton) {
        applyTrait(.italic, isOn: sender.state == .on)
    }

    @objc func toggleStrikethrough(_ sender: NSButton) {
        let value = sender.state == .on ? NSUnderlineStyle.single.rawValue : 0
        applyAttribute(.strikethroughStyle, value: value as NSObject)
    }

    // MARK: - Bullets

    @objc func toggleBullets(_ sender: NSButton) {
        performToggleBullets()
    }

    private func performToggleBullets() {
        guard let storage = textView.textStorage else { return }
        var paraInfos: [(range: NSRange, code: Int)] = []
        enumerateParagraphs(in: textView.selectedRange(), storage: storage) { pr in
            let code = (storage.attribute(.odtBlockType, at: pr.location,
                                          effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            paraInfos.append((pr, code))
        }

        let nonImageInfos = paraInfos.filter { $0.code != -1 }
        let allAreLists   = nonImageInfos.allSatisfy { $0.code >= 10 }

        storage.beginEditing()
        for info in paraInfos.reversed() {
            guard info.code != -1 else { continue }
            if allAreLists {
                removeBullet(from: info.range, in: storage)
            } else if info.code < 10 {
                addBullet(to: info.range, depth: 0, in: storage)
            }
        }
        storage.endEditing()
        textView.didChangeText()
        odtDocument?.markAsEdited()
        updateToolbarState()
    }

    @objc func increaseIndent(_ sender: Any) { adjustIndent(delta: +1) }
    @objc func decreaseIndent(_ sender: Any) { adjustIndent(delta: -1) }

    private func adjustIndent(delta: Int) {
        guard let storage = textView.textStorage else { return }
        var paraInfos: [(range: NSRange, code: Int)] = []
        enumerateParagraphs(in: textView.selectedRange(), storage: storage) { pr in
            let code = (storage.attribute(.odtBlockType, at: pr.location,
                                          effectiveRange: nil) as? NSNumber)?.intValue ?? 0
            paraInfos.append((pr, code))
        }

        storage.beginEditing()
        for info in paraInfos.reversed() {
            guard info.code >= 10 else { continue }
            let currentDepth = info.code - 10
            let newDepth     = currentDepth + delta
            if newDepth < 0 {
                removeBullet(from: info.range, in: storage)
            } else if newDepth <= 2 {
                changeBulletDepth(in: info.range, to: newDepth, in: storage)
            }
        }
        storage.endEditing()
        textView.didChangeText()
        odtDocument?.markAsEdited()
        updateToolbarState()
    }

    // MARK: - Insert Image

    @objc func insertImage(_ sender: Any) {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.title                  = "Insert Image"
        panel.allowedContentTypes    = [.jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.insertImage(from: url)
        }
    }

    private func insertImage(from url: URL) {
        guard let storage   = textView.textStorage,
              let imageData = try? Data(contentsOf: url),
              let nsImage   = NSImage(data: imageData) else { return }

        let ext      = url.pathExtension.lowercased().isEmpty ? "png" : url.pathExtension.lowercased()
        let uid      = UUID().uuidString.prefix(8)
        let href     = "Pictures/image_\(uid).\(ext)"

        // Store image data in the package for ODT serialization
        odtDocument?.package.pictures[href] = imageData

        // Scale to fit the editor's text width
        let maxWidth: CGFloat = 440
        let scale      = min(1.0, maxWidth / nsImage.size.width)
        let displaySize = NSSize(width:  nsImage.size.width  * scale,
                                 height: nsImage.size.height * scale)

        let attachment        = NSTextAttachment()
        attachment.image      = nsImage
        attachment.bounds     = NSRect(origin: .zero, size: displaySize)

        let attachStr = NSMutableAttributedString(attachment: attachment)
        attachStr.addAttributes([.odtBlockType: NSNumber(value: -1),
                                  .odtImageHref: href],
                                range: NSRange(location: 0, length: 1))

        // Insert the image on its own line, always followed by a newline so that any
        // text typed after the image lands in a new paragraph rather than the same one.
        // Without the trailing newline the cursor stays in the image's paragraph and
        // subsequent text gets classified as block type -1, causing silent data loss on save.
        let sel = textView.selectedRange()
        let str = storage.string as NSString
        let needsBefore = sel.location > 0 && str.character(at: sel.location - 1) != 10

        let insertion = NSMutableAttributedString()
        if needsBefore { insertion.append(NSAttributedString(string: "\n")) }
        insertion.append(attachStr)
        insertion.append(NSAttributedString(string: "\n"))

        storage.beginEditing()
        storage.replaceCharacters(in: sel, with: insertion)
        storage.endEditing()
        textView.didChangeText()
        odtDocument?.markAsEdited()
    }

    // MARK: - Insert menu actions

    @objc func insertDate(_ sender: Any) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        insertInlineText(fmt.string(from: Date()))
    }

    @objc func insertDateTime(_ sender: Any) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        insertInlineText(fmt.string(from: Date()))
    }

    @objc func insertHorizontalRule(_ sender: Any) {
        guard let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        let str = storage.string as NSString
        let needsBefore = sel.location > 0 && str.character(at: sel.location - 1) != 10

        let insertion = NSMutableAttributedString()
        if needsBefore { insertion.append(NSAttributedString(string: "\n")) }
        insertion.append(ModelRenderer.horizontalRuleAttachment())
        insertion.append(NSAttributedString(string: "\n"))

        storage.beginEditing()
        storage.replaceCharacters(in: sel, with: insertion)
        storage.endEditing()
        textView.didChangeText()
        odtDocument?.markAsEdited()
    }

    private func insertInlineText(_ text: String) {
        guard let storage = textView.textStorage else { return }
        let sel    = textView.selectedRange()
        let attrs  = textView.typingAttributes
        let insert = NSAttributedString(string: text, attributes: attrs)
        storage.beginEditing()
        storage.replaceCharacters(in: sel, with: insert)
        storage.endEditing()
        textView.setSelectedRange(NSRange(location: sel.location + (text as NSString).length,
                                          length: 0))
        textView.didChangeText()
        odtDocument?.markAsEdited()
    }

    // MARK: - Format menu actions

    @objc func menuApplyBody(_ sender: Any)     { applyBlockType(0) }
    @objc func menuApplyHeading1(_ sender: Any) { applyBlockType(1) }
    @objc func menuApplyHeading2(_ sender: Any) { applyBlockType(2) }
    @objc func menuApplyHeading3(_ sender: Any) { applyBlockType(3) }
    @objc func menuApplyHeading4(_ sender: Any) { applyBlockType(4) }

    @objc func menuToggleBold(_ sender: Any) {
        applyTrait(.bold, isOn: !currentTraitState(.bold))
        updateToolbarState()
    }

    @objc func menuToggleItalic(_ sender: Any) {
        applyTrait(.italic, isOn: !currentTraitState(.italic))
        updateToolbarState()
    }

    @objc func menuToggleStrikethrough(_ sender: Any) {
        let hasStrike = currentStrikethroughState()
        applyAttribute(.strikethroughStyle, value: (!hasStrike ? NSUnderlineStyle.single.rawValue : 0) as NSObject)
        updateToolbarState()
    }

    @objc func menuToggleList(_ sender: Any) {
        performToggleBullets()
    }

    private func currentTraitState(_ trait: NSFontDescriptor.SymbolicTraits) -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else {
            let f = textView.typingAttributes[.font] as? NSFont
            return f?.fontDescriptor.symbolicTraits.contains(trait) ?? false
        }
        let sel = textView.selectedRange()
        let probe = sel.length > 0 ? sel.location : max(0, sel.location - 1)
        guard probe < storage.length else { return false }
        let f = storage.attribute(.font, at: probe, effectiveRange: nil) as? NSFont
        return f?.fontDescriptor.symbolicTraits.contains(trait) ?? false
    }

    private func currentStrikethroughState() -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else {
            return ((textView.typingAttributes[.strikethroughStyle] as? Int) ?? 0) != 0
        }
        let sel = textView.selectedRange()
        let probe = sel.length > 0 ? sel.location : max(0, sel.location - 1)
        guard probe < storage.length else { return false }
        return ((storage.attribute(.strikethroughStyle, at: probe, effectiveRange: nil) as? Int) ?? 0) != 0
    }

    // MARK: - Bullet helpers

    private func addBullet(to paraRange: NSRange, depth: Int, in storage: NSTextStorage) {
        let code   = 10 + depth
        let bullet = bulletString(for: depth)
        let font   = ModelRenderer.font(for: 0)
        let ps     = ModelRenderer.listParagraphStyle(for: depth)

        let markerAttrs: [NSAttributedString.Key: Any] = [
            .odtBlockType: NSNumber(value: code),
            .odtListMarker: NSNumber(value: 1),
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: ps
        ]
        storage.insert(NSAttributedString(string: bullet, attributes: markerAttrs), at: paraRange.location)

        // Update attributes for the content (original paragraph length, now after the bullet)
        let contentRange = NSRange(location: paraRange.location + bullet.count,
                                   length: paraRange.length)
        if contentRange.length > 0 {
            storage.addAttribute(.odtBlockType,   value: NSNumber(value: code), range: contentRange)
            storage.addAttribute(.paragraphStyle, value: ps,                    range: contentRange)
        }
    }

    private func removeBullet(from paraRange: NSRange, in storage: NSTextStorage) {
        var markerRange = NSRange(location: NSNotFound, length: 0)
        storage.enumerateAttribute(.odtListMarker, in: paraRange, options: []) { val, r, stop in
            if (val as? NSNumber)?.intValue == 1 {
                markerRange = markerRange.location == NSNotFound ? r : NSUnionRange(markerRange, r)
            }
        }
        if markerRange.location != NSNotFound {
            storage.deleteCharacters(in: markerRange)
            let adjusted = NSRange(location: markerRange.location,
                                   length:   paraRange.length - markerRange.length)
            if adjusted.length > 0 {
                storage.addAttribute(.odtBlockType,   value: NSNumber(value: 0),                     range: adjusted)
                storage.addAttribute(.paragraphStyle, value: ModelRenderer.paragraphStyle(for: 0),   range: adjusted)
            }
        } else {
            storage.addAttribute(.odtBlockType,   value: NSNumber(value: 0),                   range: paraRange)
            storage.addAttribute(.paragraphStyle, value: ModelRenderer.paragraphStyle(for: 0), range: paraRange)
        }
    }

    private func changeBulletDepth(in paraRange: NSRange, to newDepth: Int, in storage: NSTextStorage) {
        let newCode   = 10 + newDepth
        let newBullet = bulletString(for: newDepth)
        let newPS     = ModelRenderer.listParagraphStyle(for: newDepth)

        var markerRange = NSRange(location: paraRange.location, length: 0)
        storage.enumerateAttribute(.odtListMarker, in: paraRange, options: []) { val, r, stop in
            if (val as? NSNumber)?.intValue == 1 { markerRange = r; stop.pointee = true }
        }

        let markerAttrs: [NSAttributedString.Key: Any] = [
            .odtBlockType: NSNumber(value: newCode),
            .odtListMarker: NSNumber(value: 1),
            .font: ModelRenderer.font(for: 0),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: newPS
        ]
        storage.replaceCharacters(in: markerRange,
                                  with: NSAttributedString(string: newBullet, attributes: markerAttrs))

        let contentStart  = markerRange.location + newBullet.count
        let contentLength = paraRange.length - markerRange.length
        if contentLength > 0 {
            let contentRange = NSRange(location: contentStart, length: contentLength)
            storage.addAttribute(.odtBlockType,   value: NSNumber(value: newCode), range: contentRange)
            storage.addAttribute(.paragraphStyle, value: newPS,                    range: contentRange)
        }
    }

    private func bulletString(for depth: Int) -> String {
        switch depth { case 0: return "• "; case 1: return "◦ "; default: return "▪ " }
    }

    // MARK: - Keyboard list behaviours

    private func handleReturn() -> Bool {
        guard let storage = textView.textStorage else { return false }
        let sel = textView.selectedRange()
        guard sel.length == 0 else { return false }
        let cursorLoc = sel.location
        let str = storage.string as NSString
        let paraRange = str.paragraphRange(for: NSRange(location: cursorLoc, length: 0))
        guard paraRange.location < storage.length else { return false }

        let code = (storage.attribute(.odtBlockType, at: paraRange.location,
                                      effectiveRange: nil) as? NSNumber)?.intValue ?? 0
        guard code >= 10 else { return false }

        let depth  = code - 10
        let bullet = bulletString(for: depth)
        let ps     = ModelRenderer.listParagraphStyle(for: depth)
        let font   = ModelRenderer.font(for: 0)

        var contentStart = paraRange.location
        storage.enumerateAttribute(.odtListMarker, in: paraRange, options: []) { val, r, stop in
            if (val as? NSNumber)?.intValue == 1 { contentStart = NSMaxRange(r); stop.pointee = true }
        }

        let hasNL      = paraRange.length > 0 && str.character(at: NSMaxRange(paraRange) - 1) == 10
        let contentEnd = NSMaxRange(paraRange) - (hasNL ? 1 : 0)
        let totalContent = contentEnd - contentStart

        if totalContent == 0 {
            exitListItem(paraRange: paraRange, in: storage)
            return true
        }

        let splitPoint   = min(max(cursorLoc, contentStart), contentEnd)
        let textAfter    = splitPoint < contentEnd
            ? str.substring(with: NSRange(location: splitPoint, length: contentEnd - splitPoint))
            : ""

        let markerAttrs: [NSAttributedString.Key: Any] = [
            .odtBlockType: NSNumber(value: code), .odtListMarker: NSNumber(value: 1),
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: ps
        ]
        let contentAttrs: [NSAttributedString.Key: Any] = [
            .odtBlockType: NSNumber(value: code),
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: ps
        ]

        let newPara = NSMutableAttributedString(string: "\n", attributes: contentAttrs)
        newPara.append(NSAttributedString(string: bullet, attributes: markerAttrs))
        if !textAfter.isEmpty {
            newPara.append(NSAttributedString(string: textAfter, attributes: contentAttrs))
        }

        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: splitPoint, length: contentEnd - splitPoint),
                                  with: newPara)
        storage.endEditing()
        textView.setSelectedRange(
            NSRange(location: splitPoint + 1 + (bullet as NSString).length, length: 0))
        // Reset typingAttributes so typed text doesn't inherit .odtListMarker from the bullet marker.
        textView.typingAttributes = contentAttrs
        textView.didChangeText()
        odtDocument?.markAsEdited()
        return true
    }

    private func exitListItem(paraRange: NSRange, in storage: NSTextStorage) {
        var markerRange = NSRange(location: NSNotFound, length: 0)
        storage.enumerateAttribute(.odtListMarker, in: paraRange, options: []) { val, r, stop in
            if (val as? NSNumber)?.intValue == 1 { markerRange = r; stop.pointee = true }
        }

        let ps   = ModelRenderer.paragraphStyle(for: 0)
        let font = ModelRenderer.font(for: 0)
        var newCursorLoc = paraRange.location

        storage.beginEditing()
        if markerRange.location != NSNotFound {
            storage.deleteCharacters(in: markerRange)
            let adjusted = NSRange(location: markerRange.location,
                                   length: paraRange.length - markerRange.length)
            if adjusted.length > 0 {
                storage.addAttribute(.odtBlockType,   value: NSNumber(value: 0), range: adjusted)
                storage.addAttribute(.paragraphStyle, value: ps,   range: adjusted)
                storage.addAttribute(.font,           value: font, range: adjusted)
            }
            newCursorLoc = markerRange.location
        } else {
            storage.addAttribute(.odtBlockType,   value: NSNumber(value: 0), range: paraRange)
            storage.addAttribute(.paragraphStyle, value: ps,                 range: paraRange)
        }
        storage.endEditing()

        textView.setSelectedRange(NSRange(location: newCursorLoc, length: 0))
        textView.didChangeText()
        odtDocument?.markAsEdited()
        updateToolbarState()
    }

    private func handleTab() -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let loc  = min(textView.selectedRange().location, storage.length - 1)
        let code = (storage.attribute(.odtBlockType, at: loc,
                                      effectiveRange: nil) as? NSNumber)?.intValue ?? 0
        guard code >= 10 else { return false }
        adjustIndent(delta: +1)
        return true
    }

    private func handleShiftTab() -> Bool {
        guard let storage = textView.textStorage, storage.length > 0 else { return false }
        let loc  = min(textView.selectedRange().location, storage.length - 1)
        let code = (storage.attribute(.odtBlockType, at: loc,
                                      effectiveRange: nil) as? NSNumber)?.intValue ?? 0
        guard code >= 10 else { return false }
        adjustIndent(delta: -1)
        return true
    }

    private func checkAutoDetectBullet() {
        guard !isAutoDetecting, let storage = textView.textStorage else { return }
        let cursorLoc = textView.selectedRange().location
        guard cursorLoc >= 2 else { return }

        let str       = storage.string as NSString
        let paraRange = str.paragraphRange(for: NSRange(location: cursorLoc, length: 0))
        let typed     = str.substring(with: NSRange(location: paraRange.location,
                                                     length: cursorLoc - paraRange.location))
        guard typed == "- " || typed == "* " else { return }

        let code = (storage.attribute(.odtBlockType, at: paraRange.location,
                                       effectiveRange: nil) as? NSNumber)?.intValue ?? 0
        guard code < 10 else { return }

        isAutoDetecting = true
        defer { isAutoDetecting = false }

        let bullet      = bulletString(for: 0)
        let ps          = ModelRenderer.listParagraphStyle(for: 0)
        let font        = ModelRenderer.font(for: 0)
        let markerAttrs: [NSAttributedString.Key: Any] = [
            .odtBlockType: NSNumber(value: 10), .odtListMarker: NSNumber(value: 1),
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: ps
        ]

        let triggerRange   = NSRange(location: paraRange.location, length: 2)
        let remainderLen   = paraRange.length - 2

        storage.beginEditing()
        storage.replaceCharacters(in: triggerRange,
                                  with: NSAttributedString(string: bullet, attributes: markerAttrs))
        if remainderLen > 0 {
            let contentRange = NSRange(location: paraRange.location + (bullet as NSString).length,
                                       length: remainderLen)
            storage.addAttribute(.odtBlockType,   value: NSNumber(value: 10), range: contentRange)
            storage.addAttribute(.paragraphStyle, value: ps,                  range: contentRange)
        }
        storage.endEditing()

        textView.setSelectedRange(
            NSRange(location: paraRange.location + (bullet as NSString).length, length: 0))
        textView.didChangeText()
        odtDocument?.markAsEdited()
        updateToolbarState()
    }

    // MARK: - Formatting helpers

    private func applyTrait(_ trait: NSFontDescriptor.SymbolicTraits, isOn: Bool) {
        guard let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()

        func converted(_ f: NSFont) -> NSFont? {
            var traits = f.fontDescriptor.symbolicTraits
            if isOn { traits.insert(trait) } else { traits.remove(trait) }
            return NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(traits),
                          size: f.pointSize)
        }

        if sel.length > 0 {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: sel, options: []) { val, r, _ in
                guard let f = val as? NSFont, let nf = converted(f) else { return }
                storage.addAttribute(.font, value: nf, range: r)
            }
            storage.endEditing()
            textView.didChangeText()
            odtDocument?.markAsEdited()
        } else {
            var attrs = textView.typingAttributes
            if let f = attrs[.font] as? NSFont, let nf = converted(f) {
                attrs[.font] = nf
                textView.typingAttributes = attrs
            }
        }
    }

    private func applyAttribute(_ key: NSAttributedString.Key, value: NSObject) {
        guard let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        if sel.length > 0 {
            storage.beginEditing()
            storage.addAttribute(key, value: value, range: sel)
            storage.endEditing()
            textView.didChangeText()
            odtDocument?.markAsEdited()
        } else {
            textView.typingAttributes[key] = value
        }
    }

    // MARK: - Paragraph enumeration

    private func enumerateParagraphs(in sel: NSRange,
                                     storage: NSTextStorage,
                                     _ body: (NSRange) -> Void) {
        let str = storage.string as NSString
        if sel.length == 0 {
            body(str.paragraphRange(for: sel))
            return
        }
        var pos = sel.location
        let end = NSMaxRange(sel)
        while pos < storage.length {
            let pr = str.paragraphRange(for: NSRange(location: pos, length: 0))
            body(pr)
            let next = NSMaxRange(pr)
            if next <= pos || next > end { break }
            pos = next
        }
    }

    // MARK: - Toolbar state

    func updateToolbarState() {
        guard let storage = textView.textStorage, storage.length > 0 else {
            bulletsButton?.state = .off
            return
        }
        let sel   = textView.selectedRange()
        let probe = sel.length > 0 ? sel.location : max(0, sel.location - 1)
        guard probe < storage.length else { return }

        let attrs = storage.attributes(at: probe, effectiveRange: nil)
        let code  = (attrs[.odtBlockType] as? NSNumber)?.intValue ?? 0

        bulletsButton?.state = code >= 10 ? .on : .off

        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            boldButton?.state   = traits.contains(.bold)   ? .on : .off
            italicButton?.state = traits.contains(.italic) ? .on : .off
        }

        let strike = (attrs[.strikethroughStyle] as? Int) ?? 0
        strikeButton?.state = strike != 0 ? .on : .off
    }
}

// MARK: - NSTextViewDelegate

extension EditorViewController: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        odtDocument?.markAsEdited()
        checkAutoDetectBullet()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateToolbarState()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSTextView.insertNewline(_:)) { return handleReturn() }
        if commandSelector == #selector(NSTextView.insertTab(_:))     { return handleTab() }
        if commandSelector == #selector(NSTextView.insertBacktab(_:)) { return handleShiftTab() }
        return false
    }
}

// MARK: - NSToolbarDelegate

extension EditorViewController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.bold, .italic, .strikethrough,
         .space,
         .bullets, .increaseIndent, .decreaseIndent,
         .flexibleSpace,
         .insertImage]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {

        case .bold:
            let btn = toggleButton(symbol: "bold",   label: "Bold",
                                   action: #selector(toggleBold(_:)))
            boldButton = btn;  item.view = btn;  item.label = "Bold"

        case .italic:
            let btn = toggleButton(symbol: "italic", label: "Italic",
                                   action: #selector(toggleItalic(_:)))
            italicButton = btn;  item.view = btn;  item.label = "Italic"

        case .strikethrough:
            let btn = toggleButton(symbol: "strikethrough", label: "Strikethrough",
                                   action: #selector(toggleStrikethrough(_:)))
            strikeButton = btn;  item.view = btn;  item.label = "Strikethrough"

        case .bullets:
            let btn = toggleButton(symbol: "list.bullet", label: "Bullets",
                                   action: #selector(toggleBullets(_:)))
            bulletsButton = btn;  item.view = btn;  item.label = "Bullets"

        case .increaseIndent:
            let btn = momentaryButton(symbol: "increase.indent", label: "Increase Indent",
                                      action: #selector(increaseIndent(_:)))
            item.view = btn;  item.label = "Increase Indent"

        case .decreaseIndent:
            let btn = momentaryButton(symbol: "decrease.indent", label: "Decrease Indent",
                                      action: #selector(decreaseIndent(_:)))
            item.view = btn;  item.label = "Decrease Indent"

        case .insertImage:
            let btn = momentaryButton(symbol: "photo", label: "Insert Image",
                                      action: #selector(insertImage(_:)))
            item.view = btn;  item.label = "Insert Image"

        default:
            return nil
        }

        return item
    }

    // MARK: Button factory helpers

    private func toggleButton(symbol: String,
                               label: String,
                               action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
        btn.image      = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        btn.bezelStyle = .texturedRounded
        btn.setButtonType(.toggle)
        btn.target     = self
        btn.action     = action
        return btn
    }

    private func momentaryButton(symbol: String,
                                  label: String,
                                  action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
        btn.image      = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        btn.bezelStyle = .texturedRounded
        btn.target     = self
        btn.action     = action
        return btn
    }
}

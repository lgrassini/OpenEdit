import AppKit

// MARK: - Toolbar item identifiers

private extension NSToolbarItem.Identifier {
    static let stylePicker    = NSToolbarItem.Identifier("stylePicker")
    static let bold           = NSToolbarItem.Identifier("bold")
    static let italic         = NSToolbarItem.Identifier("italic")
    static let strikethrough  = NSToolbarItem.Identifier("strikethrough")
    static let fontSize       = NSToolbarItem.Identifier("fontSize")
    static let color          = NSToolbarItem.Identifier("color")
}

// MARK: - EditorViewController

final class EditorViewController: NSViewController {

    // MARK: Text view

    private(set) var textView: NSTextView!
    weak var odtDocument: ODTDocument?
    private var hasLoaded = false

    // MARK: Toolbar controls

    private var stylePicker:   NSPopUpButton?
    private var boldButton:    NSButton?
    private var italicButton:  NSButton?
    private var strikeButton:  NSButton?
    private var fontSizeField: NSTextField?
    private var colorWell:     NSColorWell?

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
        let attrStr = ModelRenderer().render(doc.model)
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

    @objc func stylePickerChanged(_ sender: NSPopUpButton) {
        applyBlockType(sender.indexOfSelectedItem)
    }

    func applyBlockType(_ code: Int) {
        guard let storage = textView.textStorage else { return }
        let font = ModelRenderer.font(for: code)
        let ps   = ModelRenderer.paragraphStyle(for: code)
        storage.beginEditing()
        enumerateParagraphs(in: textView.selectedRange(), storage: storage) { pr in
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

    @objc func fontSizeChanged(_ sender: NSTextField) {
        let size = CGFloat(sender.doubleValue)
        guard size >= 4, size <= 288 else { return }
        guard let storage = textView.textStorage else { return }
        let sel = textView.selectedRange()
        if sel.length > 0 {
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: sel, options: []) { val, r, _ in
                guard let f = val as? NSFont,
                      let nf = NSFont(descriptor: f.fontDescriptor, size: size) else { return }
                storage.addAttribute(.font, value: nf, range: r)
            }
            storage.endEditing()
            textView.didChangeText()
            odtDocument?.markAsEdited()
        } else {
            var attrs = textView.typingAttributes
            if let f = attrs[.font] as? NSFont,
               let nf = NSFont(descriptor: f.fontDescriptor, size: size) {
                attrs[.font] = nf
                textView.typingAttributes = attrs
            }
        }
    }

    @objc func colorChanged(_ sender: NSColorWell) {
        applyAttribute(.foregroundColor, value: sender.color)
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
            stylePicker?.selectItem(at: 0)
            return
        }
        let sel   = textView.selectedRange()
        let probe = sel.length > 0 ? sel.location : max(0, sel.location - 1)
        guard probe < storage.length else { return }

        let attrs = storage.attributes(at: probe, effectiveRange: nil)
        let code  = (attrs[.odtBlockType] as? NSNumber)?.intValue ?? 0

        // Style picker — list items (code ≥ 10) show as Body
        stylePicker?.selectItem(at: code >= 10 ? 0 : max(0, min(4, code)))

        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            boldButton?.state   = traits.contains(.bold)   ? .on : .off
            italicButton?.state = traits.contains(.italic) ? .on : .off
            fontSizeField?.doubleValue = Double(font.pointSize)
        }

        let strike = (attrs[.strikethroughStyle] as? Int) ?? 0
        strikeButton?.state = strike != 0 ? .on : .off

        if let color = attrs[.foregroundColor] as? NSColor {
            colorWell?.color = color
        }
    }
}

// MARK: - NSTextViewDelegate

extension EditorViewController: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        odtDocument?.markAsEdited()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateToolbarState()
    }
}

// MARK: - NSToolbarDelegate

extension EditorViewController: NSToolbarDelegate {

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.stylePicker, .flexibleSpace,
         .bold, .italic, .strikethrough,
         .space,
         .fontSize, .color]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {

        case .stylePicker:
            let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 130, height: 24))
            picker.addItems(withTitles: ["Body", "Heading 1", "Heading 2",
                                         "Heading 3", "Heading 4"])
            picker.bezelStyle = .rounded
            picker.target     = self
            picker.action     = #selector(stylePickerChanged(_:))
            picker.widthAnchor.constraint(equalToConstant: 130).isActive = true
            stylePicker = picker
            item.view   = picker
            item.label  = "Style"

        case .bold:
            let btn = toggleButton(
                symbol: "bold",
                label:  "Bold",
                action: #selector(toggleBold(_:))
            )
            boldButton = btn
            item.view  = btn
            item.label = "Bold"

        case .italic:
            let btn = toggleButton(
                symbol: "italic",
                label:  "Italic",
                action: #selector(toggleItalic(_:))
            )
            italicButton = btn
            item.view    = btn
            item.label   = "Italic"

        case .strikethrough:
            let btn = toggleButton(
                symbol: "strikethrough",
                label:  "Strikethrough",
                action: #selector(toggleStrikethrough(_:))
            )
            strikeButton = btn
            item.view    = btn
            item.label   = "Strikethrough"

        case .fontSize:
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 44, height: 22))
            field.placeholderString = "12"
            field.alignment         = .center
            field.target            = self
            field.action            = #selector(fontSizeChanged(_:))
            field.widthAnchor.constraint(equalToConstant: 44).isActive = true
            fontSizeField = field
            item.view     = field
            item.label    = "Size"

        case .color:
            let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 36, height: 24))
            well.color  = .labelColor
            well.target = self
            well.action = #selector(colorChanged(_:))
            colorWell   = well
            item.view   = well
            item.label  = "Color"

        default:
            return nil
        }

        return item
    }

    // MARK: Toolbar helpers

    private func toggleButton(symbol: String,
                               label: String,
                               action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 32, height: 24))
        btn.image       = NSImage(systemSymbolName: symbol,
                                  accessibilityDescription: label)
        btn.bezelStyle  = .texturedRounded
        btn.setButtonType(.toggle)
        btn.target      = self
        btn.action      = action
        return btn
    }
}

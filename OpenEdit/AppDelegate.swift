import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        do {
            try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // App menu (title is replaced by the OS with the app name)
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About OpenEdit", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide OpenEdit", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit OpenEdit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "Open…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        let saveAs = NSMenuItem(title: "Save As…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAs)

        // Edit
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // Insert (submenu at bottom of Edit, separated by a divider)
        editMenu.addItem(.separator())
        let insertItem = NSMenuItem(title: "Insert", action: nil, keyEquivalent: "")
        let insertMenu = NSMenu(title: "Insert")
        insertItem.submenu = insertMenu

        insertMenu.addItem(withTitle: "Date",
                           action: #selector(EditorViewController.insertDate(_:)),
                           keyEquivalent: "")
        insertMenu.addItem(withTitle: "Date & Time",
                           action: #selector(EditorViewController.insertDateTime(_:)),
                           keyEquivalent: "")
        insertMenu.addItem(.separator())
        let imageMenuItem = NSMenuItem(title: "Image\u{2026}",
                                       action: #selector(EditorViewController.insertImage(_:)),
                                       keyEquivalent: "I")
        imageMenuItem.keyEquivalentModifierMask = [.command, .shift]
        insertMenu.addItem(imageMenuItem)
        insertMenu.addItem(withTitle: "Horizontal Rule",
                           action: #selector(EditorViewController.insertHorizontalRule(_:)),
                           keyEquivalent: "")

        editMenu.addItem(insertItem)

        // Format
        let formatItem = NSMenuItem(title: "Format", action: nil, keyEquivalent: "")
        mainMenu.addItem(formatItem)
        let formatMenu = NSMenu(title: "Format")
        formatItem.submenu = formatMenu

        // Paragraph Style submenu
        let paraStyleItem = NSMenuItem(title: "Paragraph Style", action: nil, keyEquivalent: "")
        let paraStyleMenu = NSMenu(title: "Paragraph Style")
        paraStyleItem.submenu = paraStyleMenu
        let h1Item = NSMenuItem(title: "Heading 1",
                                action: #selector(EditorViewController.menuApplyHeading1(_:)),
                                keyEquivalent: "1")
        h1Item.keyEquivalentModifierMask = [.command, .shift]
        paraStyleMenu.addItem(h1Item)
        let h2Item = NSMenuItem(title: "Heading 2",
                                action: #selector(EditorViewController.menuApplyHeading2(_:)),
                                keyEquivalent: "2")
        h2Item.keyEquivalentModifierMask = [.command, .shift]
        paraStyleMenu.addItem(h2Item)
        let h3Item = NSMenuItem(title: "Heading 3",
                                action: #selector(EditorViewController.menuApplyHeading3(_:)),
                                keyEquivalent: "3")
        h3Item.keyEquivalentModifierMask = [.command, .shift]
        paraStyleMenu.addItem(h3Item)
        let h4Item = NSMenuItem(title: "Heading 4",
                                action: #selector(EditorViewController.menuApplyHeading4(_:)),
                                keyEquivalent: "4")
        h4Item.keyEquivalentModifierMask = [.command, .shift]
        paraStyleMenu.addItem(h4Item)
        let bodyItem = NSMenuItem(title: "Body",
                                  action: #selector(EditorViewController.menuApplyBody(_:)),
                                  keyEquivalent: "b")
        bodyItem.keyEquivalentModifierMask = [.command, .shift]
        paraStyleMenu.addItem(bodyItem)
        let monoItem = NSMenuItem(title: "Monospaced",
                                  action: #selector(EditorViewController.menuApplyMonospaced(_:)),
                                  keyEquivalent: "m")
        monoItem.keyEquivalentModifierMask = [.command, .shift]
        paraStyleMenu.addItem(monoItem)
        formatMenu.addItem(paraStyleItem)
        formatMenu.addItem(.separator())

        // Character Style submenu
        let charStyleItem = NSMenuItem(title: "Character Style", action: nil, keyEquivalent: "")
        let charStyleMenu = NSMenu(title: "Character Style")
        charStyleItem.submenu = charStyleMenu
        charStyleMenu.addItem(withTitle: "Bold",
                              action: #selector(EditorViewController.menuToggleBold(_:)),
                              keyEquivalent: "b")
        charStyleMenu.addItem(withTitle: "Italic",
                              action: #selector(EditorViewController.menuToggleItalic(_:)),
                              keyEquivalent: "i")
        charStyleMenu.addItem(withTitle: "Strikethrough",
                              action: #selector(EditorViewController.menuToggleStrikethrough(_:)),
                              keyEquivalent: "")
        formatMenu.addItem(charStyleItem)
        formatMenu.addItem(.separator())

        // List
        formatMenu.addItem(withTitle: "List",
                           action: #selector(EditorViewController.menuToggleList(_:)),
                           keyEquivalent: "")
        formatMenu.addItem(.separator())

        // Font and Colors
        formatMenu.addItem(withTitle: "Font\u{2026}",
                           action: #selector(NSFontManager.orderFrontFontPanel(_:)),
                           keyEquivalent: "t")
        formatMenu.addItem(withTitle: "Colors\u{2026}",
                           action: #selector(NSApplication.orderFrontColorPanel(_:)),
                           keyEquivalent: "C")

        // View
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")

        // Window
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }
}

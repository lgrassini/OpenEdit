import AppKit

class ODTDocument: NSDocument {

    var package: ODTPackage = .makeEmpty()
    var model: DocumentModel = DocumentModel()
    private(set) weak var editorViewController: EditorViewController?

    override init() {
        super.init()
    }

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.minSize = NSSize(width: 480, height: 320)

        let editorVC = EditorViewController()
        editorVC.odtDocument = self
        editorViewController = editorVC
        window.contentViewController = editorVC

        let wc = DocumentWindowController(window: window)
        addWindowController(wc)
    }

    // MARK: - Dirty-state

    func markAsEdited() {
        updateChangeCount(.changeDone)
    }

    // MARK: - Read / Write

    override func read(from url: URL, ofType typeName: String) throws {
        package = try ODTZipReader().read(from: url)
        model = (try? ODTParser().parse(package)) ?? DocumentModel()
        // Refresh editor if window is already open (e.g., Revert to Saved)
        editorViewController?.loadFromDocument()
    }

    override func write(to url: URL, ofType typeName: String) throws {
        if let vc = editorViewController {
            model = vc.currentModel()
        }
        ODTWriter().update(&package, from: model)
        try ODTZipWriter().write(package, to: url)
    }
}

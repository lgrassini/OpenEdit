import AppKit

final class DocumentWindowController: NSWindowController {

    /// Called by NSDocument's showWindows(). Syncs title and proxy icon from the document.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        synchronizeWindowTitleWithDocumentName()
    }

    /// NSDocument calls this automatically when fileURL changes (after Save / Save As).
    /// We relay it to the window so the title bar and proxy icon stay current.
    override func synchronizeWindowTitleWithDocumentName() {
        super.synchronizeWindowTitleWithDocumentName()
        if let doc = document {
            window?.title = doc.displayName
            window?.representedURL = doc.fileURL
        }
    }
}

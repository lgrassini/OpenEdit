import Foundation

final class ODTZipWriter {

    func write(_ package: ODTPackage, to url: URL) throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("odt_write_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Lay out files in the staging directory
        let mimetype = "application/vnd.oasis.opendocument.text"
        try Data(mimetype.utf8).write(to: tmp.appendingPathComponent("mimetype"))
        try package.contentXML.write(to: tmp.appendingPathComponent("content.xml"))
        try package.stylesXML.write(to: tmp.appendingPathComponent("styles.xml"))

        let metaDir = tmp.appendingPathComponent("META-INF")
        try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        try package.manifestXML.write(to: metaDir.appendingPathComponent("manifest.xml"))

        if !package.pictures.isEmpty {
            let picDir = tmp.appendingPathComponent("Pictures")
            try FileManager.default.createDirectory(at: picDir, withIntermediateDirectories: true)
            for (path, data) in package.pictures {
                let name = URL(fileURLWithPath: path).lastPathComponent
                try data.write(to: picDir.appendingPathComponent(name))
            }
        }

        // Build the ZIP — mimetype must be first and stored uncompressed (-0)
        let zipURL = tmp.appendingPathComponent("output.odt")
        try runZip(in: tmp, arguments: ["-0", zipURL.path, "mimetype"])

        // Add remaining entries
        var rest = ["META-INF", "content.xml", "styles.xml"]
        if !package.pictures.isEmpty { rest.append("Pictures") }
        try runZip(in: tmp, arguments: ["-r", zipURL.path] + rest)

        // Atomically replace destination
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.moveItem(at: zipURL, to: url)
    }

    // MARK: - Helpers

    private func runZip(in directory: URL, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        proc.currentDirectoryURL = directory
        proc.arguments = arguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            throw ODTError.processLaunchFailed
        }
        proc.waitUntilExit()
        // zip exit code 12 = "nothing to do" (empty archive) — acceptable
        guard proc.terminationStatus == 0 || proc.terminationStatus == 12 else {
            throw ODTError.processFailed(proc.terminationStatus)
        }
    }
}

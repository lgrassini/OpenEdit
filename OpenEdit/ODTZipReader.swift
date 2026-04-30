import Foundation

enum ODTError: LocalizedError {
    case processLaunchFailed
    case processFailed(Int32)
    case missingFile(String)
    case invalidMimetype

    var errorDescription: String? {
        switch self {
        case .processLaunchFailed:       return "Failed to launch zip tool"
        case .processFailed(let code):   return "Zip process exited with code \(code)"
        case .missingFile(let name):     return "ODT is missing required file: \(name)"
        case .invalidMimetype:           return "Not a valid ODT file (wrong mimetype)"
        }
    }
}

final class ODTZipReader {

    func read(from url: URL) throws -> ODTPackage {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("odt_read_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        try runProcess(executable: "/usr/bin/unzip",
                       arguments: ["-o", url.path, "-d", tmp.path])

        // Validate mimetype
        if let mimeData = try? Data(contentsOf: tmp.appendingPathComponent("mimetype")),
           let mime = String(data: mimeData, encoding: .utf8) {
            guard mime.trimmingCharacters(in: .whitespacesAndNewlines)
                    == "application/vnd.oasis.opendocument.text" else {
                throw ODTError.invalidMimetype
            }
        }

        let contentXML  = try readRequired("content.xml", in: tmp)
        let stylesXML   = try readRequired("styles.xml",  in: tmp)
        let manifestXML = try readRequired("META-INF/manifest.xml", in: tmp)

        // Collect any embedded pictures
        var pictures: [String: Data] = [:]
        let picDir = tmp.appendingPathComponent("Pictures")
        if let items = try? FileManager.default.contentsOfDirectory(atPath: picDir.path) {
            for item in items {
                let fileURL = picDir.appendingPathComponent(item)
                if let data = try? Data(contentsOf: fileURL) {
                    pictures["Pictures/\(item)"] = data
                }
            }
        }

        return ODTPackage(
            contentXML: contentXML,
            stylesXML: stylesXML,
            manifestXML: manifestXML,
            pictures: pictures
        )
    }

    // MARK: - Helpers

    private func readRequired(_ name: String, in dir: URL) throws -> Data {
        let file = dir.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: file) else {
            throw ODTError.missingFile(name)
        }
        return data
    }

    private func runProcess(executable: String, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        // Suppress stdout/stderr
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError  = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            throw ODTError.processLaunchFailed
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw ODTError.processFailed(proc.terminationStatus)
        }
    }
}

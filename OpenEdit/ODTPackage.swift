import Foundation

struct ODTPackage {
    var contentXML: Data
    var stylesXML: Data
    var manifestXML: Data
    var pictures: [String: Data]  // key: "Pictures/filename.png", value: image data

    static func makeEmpty() -> ODTPackage {
        ODTPackage(
            contentXML: emptyContentXML,
            stylesXML: ODTWriter.namedStylesXML,
            manifestXML: generateManifest(pictureNames: []),
            pictures: [:]
        )
    }

    static func generateManifest(pictureNames: [String]) -> Data {
        var entries = """
            <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
            <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
            <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
            """
        for name in pictureNames {
            let mime = name.hasSuffix(".png") ? "image/png" : "image/jpeg"
            entries += "\n    <manifest:file-entry manifest:full-path=\"\(name)\" manifest:media-type=\"\(mime)\"/>"
        }
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
            \(entries)
            </manifest:manifest>
            """
        return Data(xml.utf8)
    }
}

private let emptyContentXML = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <office:document-content \
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" \
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" \
    xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" \
    xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" \
    office:version="1.2">
    <office:automatic-styles/>
    <office:body>
    <office:text>
    <text:p/>
    </office:text>
    </office:body>
    </office:document-content>
    """.utf8)

private let emptyStylesXML = Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <office:document-styles \
    xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" \
    xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" \
    xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" \
    xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" \
    office:version="1.2">
    <office:font-face-decls/>
    <office:styles/>
    <office:automatic-styles/>
    <office:master-styles/>
    </office:document-styles>
    """.utf8)

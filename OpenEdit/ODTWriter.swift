import Foundation

final class ODTWriter {

    /// Regenerates contentXML, stylesXML, and manifestXML in `package` from `model`.
    /// Pictures are preserved as-is.
    func update(_ package: inout ODTPackage, from model: DocumentModel) {
        var styleMap:  [TextProperties: String]            = [:]
        var styleList: [(name: String, props: TextProperties)] = []

        walkRuns(model) { props in
            guard props != .plain, styleMap[props] == nil else { return }
            let name = "T\(styleList.count + 1)"
            styleMap[props] = name
            styleList.append((name: name, props: props))
        }

        package.contentXML  = buildContentXML(model: model,
                                               styleMap: styleMap,
                                               styleList: styleList)
        package.stylesXML   = Self.namedStylesXML
        package.manifestXML = ODTPackage.generateManifest(
            pictureNames: package.pictures.keys.sorted()
        )
    }

    // MARK: - Run walker

    private func walkRuns(_ model: DocumentModel, _ fn: (TextProperties) -> Void) {
        for block in model.blocks { walkBlock(block, fn) }
    }

    private func walkBlock(_ block: Block, _ fn: (TextProperties) -> Void) {
        switch block {
        case .paragraph(let p):  p.runs.forEach { fn($0.props) }
        case .heading(let h):    h.runs.forEach { fn($0.props) }
        case .list(let l):       walkList(l, fn)
        case .image:             break
        case .horizontalRule:    break
        }
    }

    private func walkList(_ list: ODTList, _ fn: (TextProperties) -> Void) {
        for item in list.items {
            item.runs.forEach { fn($0.props) }
            if let sub = item.sublist { walkList(sub, fn) }
        }
    }

    // MARK: - content.xml

    private func buildContentXML(model: DocumentModel,
                                  styleMap: [TextProperties: String],
                                  styleList: [(name: String, props: TextProperties)]) -> Data {
        var s = xmlDecl + contentOpen + ">\n"
        s += "<office:automatic-styles>\n"
        for (name, props) in styleList { s += charStyleXML(name, props) }
        s += "</office:automatic-styles>\n"
        s += "<office:body><office:text>\n"

        let blocks = model.blocks.isEmpty ? [Block.paragraph(Paragraph())] : model.blocks
        for block in blocks { s += serializeBlock(block, map: styleMap) }

        s += "</office:text></office:body>\n</office:document-content>"
        return Data(s.utf8)
    }

    private func charStyleXML(_ name: String, _ p: TextProperties) -> String {
        var a = ""
        if let b  = p.bold          { a += " fo:font-weight=\"\(b ? "bold" : "normal")\"" }
        if let i  = p.italic        { a += " fo:font-style=\"\(i ? "italic" : "normal")\"" }
        if let st = p.strikethrough { a += " style:text-line-through-style=\"\(st ? "solid" : "none")\"" }
        if let fn = p.fontName      { a += " style:font-name=\"\(esc(fn))\"" }
        if let fz = p.fontSize      { a += " fo:font-size=\"\(fz)pt\"" }
        if let c  = p.color         { a += " fo:color=\"\(c)\"" }
        return "<style:style style:name=\"\(name)\" style:family=\"text\">" +
               "<style:text-properties\(a)/></style:style>\n"
    }

    // MARK: - Blocks

    private func serializeBlock(_ block: Block, map: [TextProperties: String]) -> String {
        switch block {
        case .paragraph(let p):
            let sn = p.styleName.isEmpty ? "Standard" : esc(p.styleName)
            return "<text:p text:style-name=\"\(sn)\">\(runs(p.runs, map))</text:p>\n"

        case .heading(let h):
            let sn = h.styleName.isEmpty ? "Heading_20_\(h.level)" : esc(h.styleName)
            return "<text:h text:outline-level=\"\(h.level)\" text:style-name=\"\(sn)\">" +
                   "\(runs(h.runs, map))</text:h>\n"

        case .list(let l):
            return serializeList(l, map: map, root: true)

        case .image(let img):
            let frameName = "img_" + URL(fileURLWithPath: img.href)
                                         .deletingPathExtension().lastPathComponent
            let w = String(format: "%.3fcm", img.width)
            let h = String(format: "%.3fcm", img.height)
            return "<text:p text:style-name=\"Standard\">" +
                   "<draw:frame draw:name=\"\(esc(frameName))\" " +
                   "svg:width=\"\(w)\" svg:height=\"\(h)\" " +
                   "text:anchor-type=\"paragraph\">" +
                   "<draw:image xlink:href=\"\(esc(img.href))\" " +
                   "xlink:type=\"simple\" xlink:show=\"embed\" " +
                   "xlink:actuate=\"onLoad\"/>" +
                   "</draw:frame></text:p>\n"

        case .horizontalRule:
            return "<text:p text:style-name=\"HorizontalRule\"> </text:p>\n"
        }
    }

    private func runs(_ rawRuns: [Run], _ map: [TextProperties: String]) -> String {
        coalesce(rawRuns).map { run in
            let t = escText(run.text)
            guard let sn = map[run.props] else { return t }
            return "<text:span text:style-name=\"\(sn)\">\(t)</text:span>"
        }.joined()
    }

    private func serializeList(_ list: ODTList, map: [TextProperties: String], root: Bool) -> String {
        let styleAttr = root ? " text:style-name=\"List_1\"" : ""
        var s = "<text:list\(styleAttr)>\n"
        for item in list.items {
            s += "<text:list-item>"
            s += "<text:p text:style-name=\"List_20_Paragraph\">\(runs(item.runs, map))</text:p>"
            if let sub = item.sublist { s += serializeList(sub, map: map, root: false) }
            s += "</text:list-item>\n"
        }
        return s + "</text:list>\n"
    }

    // MARK: - Utilities

    private func coalesce(_ input: [Run]) -> [Run] {
        var out: [Run] = []
        for run in input {
            if !out.isEmpty && out[out.count - 1].props == run.props {
                out[out.count - 1].text += run.text
            } else {
                out.append(run)
            }
        }
        return out
    }

    private func escText(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func esc(_ s: String) -> String {
        escText(s).replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Static XML constants

    private let xmlDecl = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"

    private let contentOpen =
        "<office:document-content" +
        " xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\"" +
        " xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\"" +
        " xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\"" +
        " xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\"" +
        " xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\"" +
        " xmlns:xlink=\"http://www.w3.org/1999/xlink\"" +
        " xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\"" +
        " office:version=\"1.2\""

    // Named paragraph styles + list style shared across all documents.
    static let namedStylesXML = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <office:document-styles \
        xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" \
        xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" \
        xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" \
        xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" \
        office:version="1.2">
        <office:font-face-decls/>
        <office:styles>
        <style:default-style style:family="paragraph">
        <style:paragraph-properties fo:margin-top="0cm" fo:margin-bottom="0.212cm"/>
        <style:text-properties fo:font-size="12pt"/>
        </style:default-style>
        <style:style style:name="Standard" style:family="paragraph" style:class="text"/>
        <style:style style:name="Text_20_Body" style:display-name="Text Body" \
        style:family="paragraph" style:parent-style-name="Standard"/>
        <style:style style:name="Heading_20_1" style:display-name="Heading 1" \
        style:family="paragraph" style:parent-style-name="Standard">
        <style:text-properties fo:font-size="20pt" fo:font-weight="bold"/>
        </style:style>
        <style:style style:name="Heading_20_2" style:display-name="Heading 2" \
        style:family="paragraph" style:parent-style-name="Standard">
        <style:text-properties fo:font-size="17pt" fo:font-weight="bold"/>
        </style:style>
        <style:style style:name="Heading_20_3" style:display-name="Heading 3" \
        style:family="paragraph" style:parent-style-name="Standard">
        <style:text-properties fo:font-size="14pt" fo:font-weight="bold"/>
        </style:style>
        <style:style style:name="Heading_20_4" style:display-name="Heading 4" \
        style:family="paragraph" style:parent-style-name="Standard">
        <style:text-properties fo:font-size="12pt" fo:font-weight="bold"/>
        </style:style>
        <style:style style:name="List_20_Paragraph" style:display-name="List Paragraph" \
        style:family="paragraph" style:parent-style-name="Standard">
        <style:paragraph-properties fo:margin-left="0.635cm"/>
        </style:style>
        <style:style style:name="HorizontalRule" \
        style:display-name="Horizontal Rule" \
        style:family="paragraph" style:parent-style-name="Standard">
        <style:paragraph-properties fo:border-bottom="0.5pt solid #808080" \
        fo:padding-bottom="1mm" fo:margin-top="3mm" fo:margin-bottom="3mm"/>
        </style:style>
        <text:list-style style:name="List_1">
        <text:list-level-style-bullet text:level="1" text:bullet-char="•">
        <style:list-level-properties text:space-before="0.635cm" \
        text:min-label-width="0.635cm"/>
        </text:list-level-style-bullet>
        <text:list-level-style-bullet text:level="2" text:bullet-char="◦">
        <style:list-level-properties text:space-before="1.27cm" \
        text:min-label-width="0.635cm"/>
        </text:list-level-style-bullet>
        <text:list-level-style-bullet text:level="3" text:bullet-char="▪">
        <style:list-level-properties text:space-before="1.905cm" \
        text:min-label-width="0.635cm"/>
        </text:list-level-style-bullet>
        </text:list-style>
        </office:styles>
        <office:automatic-styles/>
        <office:master-styles/>
        </office:document-styles>
        """.utf8)
}

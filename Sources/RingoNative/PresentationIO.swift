import Foundation
import RingoCore
import RingoDomain

/// Writes a minimal, standards-conformant PPTX where each slide is one full-bleed picture.
/// Used for PDF → PPTX "pages as images" (nothing becomes editable; see docs/FORMATS.md).
public enum PPTXWriter {
    /// - Parameters:
    ///   - slides: JPEG data per slide.
    ///   - size: slide size in points (from the first PDF page).
    public static func write(slides: [Data], size: CGSize, to url: URL) throws {
        let emu = 12700.0
        let cx = Int(size.width * emu), cy = Int(size.height * emu)
        let z = ZipWriter()
        let n = slides.count
        z.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Default Extension="jpeg" ContentType="image/jpeg"/>
        <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
        <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
        <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
        <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        \((1...max(n, 1)).prefix(n).map { "<Override PartName=\"/ppt/slides/slide\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>" }.joined())
        </Types>
        """)
        z.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """)
        z.add("docProps/app.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Ringo</Application><Slides>\(n)</Slides></Properties>
        """)
        z.add("docProps/core.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>Ringo</dc:creator></cp:coreProperties>
        """)
        let slideIds = (0..<n).map { "<p:sldId id=\"\(256 + $0)\" r:id=\"rId\($0 + 2)\"/>" }.joined()
        z.add("ppt/presentation.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
        <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
        <p:sldIdLst>\(slideIds)</p:sldIdLst>
        <p:sldSz cx="\(cx)" cy="\(cy)"/>
        <p:notesSz cx="6858000" cy="9144000"/>
        </p:presentation>
        """)
        var presRels = "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        for i in 0..<n {
            presRels += "<Relationship Id=\"rId\(i + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(i + 1).xml\"/>"
        }
        presRels += "<Relationship Id=\"rId\(n + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"theme/theme1.xml\"/>"
        z.add("ppt/_rels/presentation.xml.rels", rels(presRels))

        let emptyTree = """
        <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>
        """
        z.add("ppt/slideMasters/slideMaster1.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
        \(emptyTree)
        <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
        <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
        </p:sldMaster>
        """)
        z.add("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels("""
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
        """))
        z.add("ppt/slideLayouts/slideLayout1.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1">
        \(emptyTree.replacingOccurrences(of: "<p:cSld>", with: "<p:cSld name=\"Blank\">"))
        <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
        </p:sldLayout>
        """)
        z.add("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels("""
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
        """))
        z.add("ppt/theme/theme1.xml", theme)
        for (i, jpeg) in slides.enumerated() {
            z.add("ppt/media/image\(i + 1).jpeg", jpeg, store: true)
            z.add("ppt/slides/slide\(i + 1).xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
            <p:cSld><p:spTree>
            <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
            <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
            <p:pic><p:nvPicPr><p:cNvPr id="2" name="Page \(i + 1)" descr="Page \(i + 1)"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>
            <p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>
            <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>
            </p:spTree></p:cSld>
            <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
            </p:sld>
            """)
            z.add("ppt/slides/_rels/slide\(i + 1).xml.rels", rels("""
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
            <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image\(i + 1).jpeg"/>
            """))
        }
        try z.finish().write(to: url)
    }

    static func rels(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(body)</Relationships>
        """
    }

    static let theme = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Ringo">
    <a:themeElements>
    <a:clrScheme name="Office">
    <a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
    <a:dk2><a:srgbClr val="1F497D"/></a:dk2><a:lt2><a:srgbClr val="EEECE1"/></a:lt2>
    <a:accent1><a:srgbClr val="4F81BD"/></a:accent1><a:accent2><a:srgbClr val="C0504D"/></a:accent2><a:accent3><a:srgbClr val="9BBB59"/></a:accent3>
    <a:accent4><a:srgbClr val="8064A2"/></a:accent4><a:accent5><a:srgbClr val="4BACC6"/></a:accent5><a:accent6><a:srgbClr val="F79646"/></a:accent6>
    <a:hlink><a:srgbClr val="0000FF"/></a:hlink><a:folHlink><a:srgbClr val="800080"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>
    <a:fmtScheme name="Office">
    <a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>
    <a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="25400"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="38100"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>
    <a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>
    <a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>
    </a:fmtScheme>
    </a:themeElements>
    </a:theme>
    """
}

import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
@testable import RingoCore
import RingoDomain
@testable import RingoNative
import RingoEngine
import RingoSettings

/// Generates test fixtures on the fly in a private temporary directory.
final class Fixtures {
    let dir: URL

    init(_ name: String = #function) throws {
        let safe = name.filter { $0.isLetter || $0.isNumber }
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ringo-tests").appendingPathComponent("\(safe)-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    /// Settings in the fixture directory, so tests never touch the user's real settings.
    lazy var settings = SettingsStore(fileURL: url("settings.json"))

    func service() -> RingoService { RingoEngine.makeService(settingsStore: settings) }

    // MARK: Images

    @discardableResult
    func png(_ name: String = "image.png", width: Int = 64, height: Int = 48, alpha: Bool = true) throws -> URL {
        let ctx = ImageIOSupport.makeContext(width: width, height: height, opaque: !alpha)!
        ctx.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.1, alpha: alpha ? 0.5 : 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        let u = url(name)
        try ImageIOSupport.write([ctx.makeImage()!], to: u, format: "png")
        return u
    }

    /// JPEG with EXIF (camera model), GPS and an orientation tag.
    @discardableResult
    func jpegWithGPS(_ name: String = "gps.jpg", orientation: Int = 1) throws -> URL {
        let ctx = ImageIOSupport.makeContext(width: 80, height: 60, opaque: true)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 80, height: 60))
        let u = url(name)
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.5, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 127.0, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private comment", kCGImagePropertyExifLensModel: "TestLens"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "RingoCam", kCGImagePropertyTIFFArtist: "Secret Person", kCGImagePropertyTIFFOrientation: orientation],
        ]
        try ImageIOSupport.write([ctx.makeImage()!], to: u, format: "jpeg", quality: 0.9, frameProperties: [props])
        return u
    }

    /// Image with rendered text, for OCR-based redaction.
    @discardableResult
    @MainActor
    func textImage(_ name: String, lines: [String]) throws -> URL {
        let w = 1000, h = 140 * lines.count + 60
        let ctx = ImageIOSupport.makeContext(width: w, height: h, opaque: true)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(at: CGPoint(x: 40, y: h - 120 - i * 140), withAttributes: [.font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        let u = url(name)
        try ImageIOSupport.write([ctx.makeImage()!], to: u, format: "png")
        return u
    }

    // MARK: PDF

    /// Multi-page PDF with a real text layer, US Letter pages.
    @discardableResult
    @MainActor
    func textPDF(_ name: String = "doc.pdf", pages: [String]) throws -> URL {
        let u = url(name)
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(url: u as CFURL)!, mediaBox: &media, [kCGPDFContextAuthor: "Secret Author", kCGPDFContextTitle: "Fixture"] as CFDictionary)!
        for text in pages {
            ctx.beginPDFPage(nil)
            let gc = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = gc
            (text as NSString).draw(in: CGRect(x: 72, y: 72, width: 468, height: 648), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return u
    }

    // MARK: Text formats

    @discardableResult
    func write(_ name: String, _ text: String) throws -> URL {
        let u = url(name)
        try text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    @discardableResult
    func data(_ name: String, _ d: Data) throws -> URL {
        let u = url(name)
        try d.write(to: u)
        return u
    }

    @discardableResult
    func wav(_ name: String = "tone.wav", seconds: Double = 0.5) throws -> URL {
        let u = url(name)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let file = try AVAudioFile(forWriting: u, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
                                                            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
        let frames = AVAudioFrameCount(44100 * seconds)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        for i in 0..<Int(frames) { buf.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44100) * 0.3) }
        try file.write(from: buf)
        return u
    }

    /// A ZIP built entry by entry (lets tests create malicious archives).
    @discardableResult
    func zip(_ name: String, entries: [(String, String)]) throws -> URL {
        let z = ZipWriter()
        for (n, c) in entries { z.add(n, c) }
        return try data(name, z.finish())
    }
}


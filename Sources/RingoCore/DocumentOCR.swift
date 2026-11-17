import Foundation
import RingoDomain

/// Recognition is separate from export so every OCR backend can feed the same document writers.
public struct RecognizedDocument: Sendable {
    public var text: String
    public var isMarkdown: Bool
    public init(_ text: String, isMarkdown: Bool = false) {
        self.text = text; self.isMarkdown = isMarkdown
    }
}

public protocol DocumentOCRBackend: Sendable {
    var id: ProviderID { get }
    var name: String { get }
    var acceptsPDF: Bool { get }
    func status() -> ProviderStatus
    func recognize(_ input: URL, context: JobContext) async throws -> RecognizedDocument
}

public enum OCRFormats {
    public static let images: [FormatID] = ["png", "jpeg", "tiff", "heic", "bmp", "webp"]
    public static let outputs: [FormatID] = ["txt", "md", "html", "docx", "epub", "xlsx"]
    public static func supports(_ from: FormatID, _ to: FormatID) -> Bool {
        (from == "pdf" || images.contains(from)) && outputs.contains(to)
    }
}

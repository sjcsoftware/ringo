import AppKit
import Foundation

/// Reads the current Finder selection through Finder's scripting interface (Apple Events).
///
/// Why scripting: macOS has no public API that returns another app's selection, and guessing from the
/// pointer position would be wrong. The first call shows the system Automation consent prompt
/// ("Ringo wants to control Finder"); only `get selection` is ever sent.
public enum FinderSelection {
    public enum Failure: Error, Equatable, Sendable {
        case finderNotFrontmost(frontmost: String?)
        case finderNotRunning
        case emptySelection
        case automationDenied
        case scriptError(String)

        public var message: String {
            switch self {
            case .finderNotFrontmost(let app): "Select files in Finder first\(app.map { " (\($0) is in front)" } ?? "")."
            case .finderNotRunning: "Finder is not running."
            case .emptySelection: "Nothing is selected in Finder."
            case .automationDenied: "Ringo is not allowed to read the Finder selection. Allow it in System Settings → Privacy & Security → Automation."
            case .scriptError(let m): "Finder did not return a selection (\(m))."
            }
        }
    }

    static let finderID = "com.apple.finder"

    public static var finderIsFrontmost: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier == finderID }

    /// Must be called on the main thread (NSAppleScript is not thread-safe).
    @MainActor
    public static func current(requireFrontmost: Bool) -> Result<[URL], Failure> {
        let front = NSWorkspace.shared.frontmostApplication
        if requireFrontmost && front?.bundleIdentifier != finderID {
            return .failure(.finderNotFrontmost(frontmost: front?.localizedName))
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: finderID).first != nil else { return .failure(.finderNotRunning) }
        // A hung Finder must not freeze the menu for AppleScript's default two minutes.
        let source = """
        with timeout of 5 seconds
          tell application id "com.apple.finder"
            set out to {}
            repeat with x in (get selection)
              set end of out to POSIX path of (x as alias)
            end repeat
            return out
          end tell
        end timeout
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failure(.scriptError("could not compile")) }
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            if code == -1743 || code == -1744 { return .failure(.automationDenied) }
            if code == -1712 { return .failure(.scriptError("Finder did not answer within 5 seconds. If macOS asked for permission, choose Allow and try again")) }
            return .failure(.scriptError(error[NSAppleScript.errorMessage] as? String ?? "error \(code)"))
        }
        var urls: [URL] = []
        if result.numberOfItems > 0 {
            for i in 1...result.numberOfItems {
                if let p = result.atIndex(i)?.stringValue { urls.append(URL(fileURLWithPath: p)) }
            }
        } else if let p = result.stringValue, !p.isEmpty {
            urls.append(URL(fileURLWithPath: p))
        }
        // Finder returns folders with a trailing slash; normalize, keep order, drop duplicates.
        var seen = Set<String>()
        urls = urls.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
        return urls.isEmpty ? .failure(.emptySelection) : .success(urls)
    }

    /// Automation permission status for Finder without prompting.
    public static func automationStatus() -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: finderID)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
    }

    public static var automationAllowed: Bool { automationStatus() == noErr }

    public static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
    }
}

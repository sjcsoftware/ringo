import Foundation
import RingoCore
import RingoDomain

/// Audio/video breadth through a locally installed FFmpeg. Never bundled (GPL/LGPL and patent
/// implications are left to the user's build; see SECURITY.md).
public final class FFmpegProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "ffmpeg"
    public let name = "FFmpeg"
    public let defaultPriority = 30
    public let isOptional = true
    public let ffmpeg = ExternalTool("ffmpeg", versionArgs: ["-hide_banner", "-version"])
    public let ffprobe = ExternalTool("ffprobe", versionArgs: ["-hide_banner", "-version"])
    static let hint = "Install it with `brew install ffmpeg`."

    private let lock = NSLock()
    private var encoderCache: Set<String>?

    public static let audio: [FormatID] = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma"]
    public static let video: [FormatID] = ["mp4", "mov", "mkv", "webm", "avi", "wmv"]

    public init() {}

    /// Encoder each target needs. `ogg` accepts any of several (see `oggEncoder`).
    static func requirement(_ to: FormatID) -> String? {
        switch to.rawValue {
        case "mp3": "libmp3lame"
        case "m4a": "aac"
        case "flac": "flac"
        case "opus": "libopus"
        case "ogg": "ogg"
        case "wma": "wmav2"
        case "webm": "libvpx-vp9"
        case "wmv": "wmv2"
        case "mp4", "mov", "avi": "h264"
        case "gif": "gif"
        default: nil
        }
    }

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        for a in Self.audio {
            for b in Self.audio where b != a {
                out.append(EdgeSpec(a, b, Self.audioFidelity(b), limitations: Self.audioLimits(b), requirement: Self.requirement(b), cost: 2))
            }
        }
        for v in Self.video {
            for w in Self.video where w != v {
                var lim = ["Streams are copied when the codecs fit \(w.rawValue.uppercased()); otherwise video is re-encoded (\(Self.videoCodecLabel(w)))."]
                if w != "mkv" { lim.append("Subtitle and attachment streams are kept only for MKV targets.") }
                lim.append("HDR sources re-encoded to 8-bit codecs are not tone-mapped.")
                out.append(EdgeSpec(v, w, .remux, limitations: lim, requirement: Self.requirement(w), cost: 4))
            }
            for a in Self.audio {
                out.append(EdgeSpec(v, a, Self.audioFidelity(a), limitations: ["Extracts the first audio track. Fails clearly when the video has no audio."] + Self.audioLimits(a),
                                    requirement: Self.requirement(a), cost: 2))
            }
            out.append(EdgeSpec(v, "gif", .lossy, limitations: ["Two-pass palette: 12 fps, at most 480 px wide, first 15 s by default (--fps, --max-width, --max-duration)."],
                                requirement: "gif", cost: 4))
        }
        for w in ["mp4", "webm", "mov"] as [FormatID] {
            out.append(EdgeSpec("gif", w, .lossy, limitations: ["Animated GIF to video; transparency is flattened."], requirement: Self.requirement(w), cost: 3))
        }
        return out
    }

    static func audioFidelity(_ f: FormatID) -> Fidelity {
        ["wav", "flac", "aiff"].contains(f.rawValue) ? .lossless : .lossy
    }

    static func audioLimits(_ f: FormatID) -> [String] {
        switch f.rawValue {
        case "mp3": ["MP3 via LAME, 192 kbps by default (--audio-bitrate)."]
        case "m4a": ["AAC in MPEG-4, 192 kbps by default."]
        case "ogg": ["Ogg container. Vorbis when the encoder exists (libvorbis, or FFmpeg's experimental native encoder); otherwise Opus inside .ogg (reported in the result)."]
        case "opus": ["Opus codec in an Ogg container, 128 kbps by default; resampled to 48 kHz."]
        case "wma": ["Windows Media Audio 2 (wmav2), 192 kbps."]
        case "flac", "wav", "aiff": ["Lossless container; quality cannot exceed the source."]
        default: []
        }
    }

    static func videoCodecLabel(_ f: FormatID) -> String {
        switch f.rawValue {
        case "webm": "VP9 + Opus"
        case "wmv": "WMV2 + WMA2"
        case "avi": "H.264 + MP3"
        case "mkv": "H.264 + AAC"
        default: "H.264 + AAC"
        }
    }

    public func status() -> ProviderStatus {
        let installed = ffmpeg.installed && ffprobe.installed
        return ProviderStatus(id: id, name: name, kind: .external, installed: installed, version: installed ? ffmpeg.version : nil,
                              path: ffmpeg.url?.path, license: "LGPL/GPL depending on build (user-installed, not bundled)",
                              installHint: Self.hint, notes: installed ? ["Encoders checked: " + Self.interesting.filter(encoders().contains).joined(separator: ", ")] : [])
    }

    static let interesting = ["libmp3lame", "aac", "flac", "libopus", "libvorbis", "vorbis", "wmav2", "libx264", "h264_videotoolbox", "libx265",
                              "libvpx-vp9", "libsvtav1", "wmv2", "mpeg4", "gif", "libwebp", "libaom-av1"]

    public func encoders() -> Set<String> {
        lock.lock()
        if let encoderCache { lock.unlock(); return encoderCache }
        lock.unlock()
        var set = Set<String>()
        if let url = ffmpeg.url, let cached = ProbeCache.load(binary: url, key: "encoders") {
            set = Set(cached)
        } else if let url = ffmpeg.url {
            let p = Process()
            p.executableURL = url
            p.arguments = ["-hide_banner", "-encoders"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            if (try? p.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    if parts.count >= 2, parts[0].count == 6 { set.insert(String(parts[1])) }
                }
                ProbeCache.store(binary: url, key: "encoders", value: set.sorted())
            }
        }
        lock.lock(); encoderCache = set; lock.unlock()
        return set
    }

    public var oggEncoder: (codec: String, extra: [String], label: String)? {
        let e = encoders()
        if e.contains("libvorbis") { return ("libvorbis", ["-q:a", "5"], "Vorbis") }
        if e.contains("vorbis") { return ("vorbis", ["-strict", "experimental", "-q:a", "5", "-ac", "2"], "Vorbis (FFmpeg native, experimental)") }
        if e.contains("libopus") { return ("libopus", ["-b:a", "128k"], "Opus") }
        return nil
    }

    public var h264Encoder: String? {
        let e = encoders()
        if e.contains("libx264") { return "libx264" }
        if e.contains("h264_videotoolbox") { return "h264_videotoolbox" }
        return nil
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) {
        guard ffmpeg.installed, ffprobe.installed else { return (false, "Requires FFmpeg. \(Self.hint)") }
        guard let req = edge.requirement else { return (true, nil) }
        let e = encoders()
        switch req {
        case "ogg": return oggEncoder != nil ? (true, nil) : (false, "This FFmpeg build has no Vorbis or Opus encoder.")
        case "h264": return h264Encoder != nil ? (true, nil) : (false, "This FFmpeg build has no H.264 encoder (libx264 or VideoToolbox).")
        default: return e.contains(req) ? (true, nil) : (false, "This FFmpeg build lacks the \(req) encoder. Install a full build: `brew install ffmpeg`.")
        }
    }

    // MARK: - Probe

    public struct Probe: Sendable {
        public var duration: Double
        public var streams: [[String: String]]
        public var videoCodec: String? { streams.first { $0["codec_type"] == "video" && $0["disposition_attached_pic"] != "1" }?["codec_name"] }
        public var audioCodec: String? { streams.first { $0["codec_type"] == "audio" }?["codec_name"] }
        public var hasAudio: Bool { streams.contains { $0["codec_type"] == "audio" } }
        public var hasVideo: Bool { streams.contains { $0["codec_type"] == "video" && $0["disposition_attached_pic"] != "1" } }
        public var subtitleCount: Int { streams.filter { $0["codec_type"] == "subtitle" }.count }
        public var audioCount: Int { streams.filter { $0["codec_type"] == "audio" }.count }
        public var isHDR: Bool { streams.contains { ["smpte2084", "arib-std-b67"].contains($0["color_transfer"] ?? "") } }
        public var hasAlpha: Bool { streams.contains { ($0["pix_fmt"] ?? "").contains("a") && ($0["pix_fmt"] ?? "").hasPrefix("yuva") } }
    }

    public func probe(_ path: String, timeout: TimeInterval = 60) async throws -> Probe {
        let url = try ffprobe.require(name, hint: Self.hint)
        let r = try await Subprocess.run(url, ["-v", "error", "-print_format", "json", "-show_streams", "-show_format", "file:" + path], timeout: timeout)
        guard r.status == 0, let json = try? JSONSerialization.jsonObject(with: r.stdout) as? [String: Any] else {
            throw RingoError.inputUnreadable((path as NSString).lastPathComponent, reason: "FFmpeg cannot read this media file (\(r.stderrTail))")
        }
        let format = json["format"] as? [String: Any] ?? [:]
        let duration = Double(format["duration"] as? String ?? "") ?? 0
        let streams = (json["streams"] as? [[String: Any]] ?? []).map { s -> [String: String] in
            var d: [String: String] = [:]
            for (k, v) in s { if let str = v as? String { d[k] = str } else if let n = v as? NSNumber { d[k] = n.stringValue } }
            if let disp = s["disposition"] as? [String: Any], let ap = disp["attached_pic"] as? NSNumber { d["disposition_attached_pic"] = ap.stringValue }
            return d
        }
        return Probe(duration: duration, streams: streams)
    }

    // MARK: - Convert

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let exe = try ffmpeg.require(name, hint: Self.hint)
        let probe = try await probe(request.inputPath)
        let out = context.outputURL(ext: request.targetExtension)
        let to = request.to
        var warnings: [String] = []
        var details: [String: String] = [:]
        var fidelity: Fidelity?
        var args = ["-hide_banner", "-nostdin", "-y", "-v", "error", "-progress", "pipe:1", "-nostats"]
        if request.from == "gif" { args += ["-f", "gif"] }
        args += ["-i", "file:" + request.inputPath]
        args += request.options.stripMetadata ? ["-map_metadata", "-1"] : ["-map_metadata", "0"]

        var duration = probe.duration
        if Self.audio.contains(to) {
            guard probe.hasAudio else { throw RingoError.noAudioTrack(request.input.originalPath) }
            args += ["-map", "0:a:0", "-vn", "-sn", "-dn"]
            args += try audioArgs(to, request.options, details: &details)
            if probe.audioCount > 1 { warnings.append("The file has \(probe.audioCount) audio tracks; the first was exported.") }
        } else if to == "gif" {
            guard probe.hasVideo else { throw RingoError.inputUnreadable(request.input.originalPath, reason: "no video stream") }
            let fps = min(max(request.options.fps ?? 12, 1), 50)
            let width = request.options.maxWidth ?? 480
            let maxDur = request.options.maxDuration ?? 15
            if probe.duration > maxDur { warnings.append("Only the first \(Int(maxDur)) s were exported (--max-duration)."); duration = maxDur }
            args += ["-t", String(maxDur), "-an", "-sn", "-filter_complex",
                     "[0:v]fps=\(fps),scale='min(\(width),iw)':-2:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a",
                     "-loop", "0"]
        } else {
            let (vargs, mode, w) = videoArgs(to, probe: probe, options: request.options)
            args += vargs
            warnings += w
            details["mode"] = mode
            fidelity = mode == "stream copy" ? .remux : .lossy
        }
        args += ["file:" + out.path]

        let total = max(duration, 0.001)
        let progress = context.progress
        let r = try await Subprocess.run(exe, args, timeout: context.timeout, onStdoutLine: { line in
            if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) {
                progress(min(max(us / 1_000_000 / total, 0), 0.99))
            }
        })
        guard r.status == 0 else {
            throw RingoError.providerFailed(provider: name, message: r.stderrTail.isEmpty ? "exit status \(r.status)" : r.stderrTail)
        }
        return ProviderOutcome(files: [ProducedFile(url: out, format: to)], warnings: warnings, details: details, fidelity: fidelity)
    }

    func audioArgs(_ to: FormatID, _ o: ConversionOptions, details: inout [String: String]) throws -> [String] {
        let kbps = o.audioBitrate
        switch to.rawValue {
        case "mp3": return ["-c:a", "libmp3lame", "-b:a", "\(kbps ?? 192)k"]
        case "m4a": return ["-c:a", "aac", "-b:a", "\(kbps ?? 192)k", "-movflags", "+faststart"]
        case "wav": return ["-c:a", "pcm_s16le"]
        case "aiff": return ["-c:a", "pcm_s16be"]
        case "flac": return ["-c:a", "flac", "-compression_level", "8"]
        case "opus": return ["-c:a", "libopus", "-b:a", "\(kbps ?? 128)k", "-f", "ogg"]
        case "wma": return ["-c:a", "wmav2", "-b:a", "\(kbps ?? 192)k"]
        case "ogg":
            guard let enc = oggEncoder else { throw RingoError.providerMissing(provider: name, hint: "This FFmpeg build has no Vorbis or Opus encoder.") }
            details["codec"] = enc.label
            var extra = enc.extra
            if let kbps, enc.codec != "libopus" { extra = ["-b:a", "\(kbps)k"] + (enc.codec == "vorbis" ? ["-strict", "experimental", "-ac", "2"] : []) }
            return ["-c:a", enc.codec] + extra + ["-f", "ogg"]
        default:
            throw RingoError.unsupportedConversion(from: "audio", to: to.rawValue, reason: "unknown audio target")
        }
    }

    static func crf(_ quality: Int?) -> String {
        let q = Double(min(max(quality ?? 85, 1), 100))
        return String(Int((35 - q * 0.18).rounded()))
    }

    func videoArgs(_ to: FormatID, probe: Probe, options: ConversionOptions) -> ([String], String, [String]) {
        var warnings: [String] = []
        let v = probe.videoCodec ?? "", a = probe.audioCodec ?? ""
        let copyOK: Bool = {
            switch to.rawValue {
            case "mkv": return true
            case "mp4", "mov": return ["h264", "hevc", "av1", "mpeg4"].contains(v) && (a.isEmpty || ["aac", "mp3", "alac", "ac3", "eac3", "opus"].contains(a))
            case "webm": return ["vp8", "vp9", "av1"].contains(v) && (a.isEmpty || ["opus", "vorbis"].contains(a))
            case "avi": return ["mpeg4", "h264", "mjpeg"].contains(v) && (a.isEmpty || ["mp3", "ac3", "pcm_s16le"].contains(a))
            case "wmv": return ["wmv1", "wmv2", "wmv3", "vc1"].contains(v) && (a.isEmpty || a.hasPrefix("wma"))
            default: return false
            }
        }()
        if copyOK && options.quality == nil && options.preset == nil {
            var args = ["-map", "0:v?", "-map", "0:a?", "-c", "copy"]
            if to == "mkv" { args = ["-map", "0", "-c", "copy"] }
            if to == "mp4" || to == "mov" { args += ["-movflags", "+faststart"] }
            if probe.subtitleCount > 0 && to != "mkv" { warnings.append("\(probe.subtitleCount) subtitle stream(s) were not carried over (\(to.rawValue.uppercased()) cannot hold them as copied).") }
            return (args, "stream copy", warnings)
        }
        var args: [String] = ["-map", "0:v:0", "-map", "0:a?"]
        let crf = Self.crf(options.quality)
        switch to.rawValue {
        case "webm":
            args += ["-c:v", "libvpx-vp9", "-crf", String(Int(crf)! + 10), "-b:v", "0", "-row-mt", "1", "-c:a", "libopus", "-b:a", "128k"]
        case "wmv":
            args += ["-c:v", "wmv2", "-q:v", "3", "-c:a", "wmav2", "-b:a", "192k"]
        case "avi":
            args += h264(crf) + ["-c:a", "libmp3lame", "-b:a", "192k"]
        default:
            args += h264(crf) + ["-c:a", "aac", "-b:a", "192k"]
            if to == "mp4" || to == "mov" { args += ["-movflags", "+faststart"] }
            if to == "mkv" { args = ["-map", "0:v:0", "-map", "0:a?", "-map", "0:s?"] + Array(args.dropFirst(4)) + ["-c:s", "copy"] }
        }
        args += ["-pix_fmt", "yuv420p"]
        if probe.isHDR && to != "mkv" { warnings.append("HDR video was re-encoded to 8-bit SDR without tone mapping; colors may look washed out.") }
        if probe.hasAlpha { warnings.append("The video's alpha channel was dropped.") }
        if probe.subtitleCount > 0 && to != "mkv" { warnings.append("\(probe.subtitleCount) subtitle stream(s) were not carried over.") }
        return (args, "re-encode", warnings)
    }

    func h264(_ crf: String) -> [String] {
        if h264Encoder == "libx264" { return ["-c:v", "libx264", "-preset", "medium", "-crf", crf] }
        return ["-c:v", "h264_videotoolbox", "-q:v", "65"]
    }
}

@preconcurrency import AVFoundation
import Foundation
import RingoCore
import RingoDomain
import RingoExternal

/// Audio/video tools. FFmpeg when installed; AVFoundation for Apple formats otherwise.
enum MediaTools {
    static let ffmpeg = FFmpegProvider()
    static let avfVideo: Set<FormatID> = ["mov", "mp4"]
    static let avfAudio: Set<FormatID> = ["m4a", "mp3", "wav", "aiff"]

    static var hasFFmpeg: Bool { ffmpeg.ffmpeg.installed && ffmpeg.ffprobe.installed }

    static func isMedia(_ f: FormatID?) -> Bool {
        guard let f else { return false }
        return FFmpegProvider.audio.contains(f) || FFmpegProvider.video.contains(f)
    }

    static func isVideo(_ f: FormatID?) -> Bool { f.map { FFmpegProvider.video.contains($0) } ?? false }

    static func supported(_ f: FormatID?) -> Bool {
        guard let f else { return false }
        return hasFFmpeg ? isMedia(f) : (avfVideo.contains(f) || avfAudio.contains(f))
    }

    static func runFFmpeg(_ args: [String], input: InputFile, out: URL, context: JobContext, duration: Double? = nil) async throws {
        let exe = try ffmpeg.ffmpeg.require("FFmpeg", hint: "Install it with `brew install ffmpeg`.")
        let total = max(duration ?? 0, 0.001)
        let progress = context.progress
        let full = ["-hide_banner", "-nostdin", "-y", "-v", "error", "-progress", "pipe:1", "-nostats"] + args + ["file:" + out.path]
        let r = try await Subprocess.run(exe, full, timeout: context.timeout, onStdoutLine: { line in
            if line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) { progress(min(max(us / 1e6 / total, 0), 0.99)) }
        })
        guard r.status == 0 else { throw RingoError.providerFailed(provider: "FFmpeg", message: r.stderrTail) }
    }

    static func ext(_ f: FormatID) -> String { FormatCatalog.require(f).primaryExtension }

    // MARK: Trim

    static func trim(_ input: InputFile, start: Double, end: Double?, context: JobContext) async throws -> ProviderOutcome {
        guard start >= 0 else { throw RingoError.invalidArgument("Trim start must be ≥ 0") }
        if let end, end <= start { throw RingoError.invalidArgument("Trim end must be after the start") }
        let format = input.format!
        let out = context.outputURL(ext: ext(format))
        if hasFFmpeg {
            let probe = try await ffmpeg.probe(input.url.path)
            if start >= probe.duration && probe.duration > 0 { throw RingoError.invalidArgument("Start \(start) s is past the end (\(String(format: "%.2f", probe.duration)) s)") }
            var args = ["-ss", String(start), "-i", "file:" + input.url.path]
            if let end { args += ["-t", String(end - start)] }
            args += ["-map", "0", "-c", "copy", "-avoid_negative_ts", "make_zero"]
            if format == "mp4" || format == "mov" || format == "m4a" { args += ["-movflags", "+faststart"] }
            try await runFFmpeg(args, input: input, out: out, context: context, duration: (end ?? probe.duration) - start)
            var o = ProviderOutcome.single(out, format)
            if probe.hasVideo { o.warnings.append("Cut without re-encoding: the start snaps to the nearest earlier keyframe.") }
            o.fidelity = .lossless
            return o
        }
        let asset = AVURLAsset(url: input.url)
        let duration = try await asset.load(.duration).seconds
        let endT = min(end ?? duration, duration)
        guard start < endT else { throw RingoError.invalidArgument("Trim range is empty (duration \(String(format: "%.2f", duration)) s)") }
        let type: AVFileType = format == "mov" ? .mov : format == "mp4" ? .mp4 : .m4a
        guard format != "wav" && format != "aiff" && format != "mp3" else {
            throw RingoError.providerMissing(provider: "FFmpeg", hint: "Trimming \(format.rawValue.uppercased()) needs FFmpeg (`brew install ffmpeg`).")
        }
        try await export(asset, preset: AVAssetExportPresetPassthrough, type: type, to: out,
                         range: CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: endT, preferredTimescale: 600)), context: context)
        var o = ProviderOutcome.single(out, format)
        o.fidelity = .lossless
        return o
    }

    static func export(_ asset: AVAsset, preset: String, type: AVFileType, to out: URL, range: CMTimeRange? = nil,
                       metadata: [AVMetadataItem]? = nil, filterForSharing: Bool = false, composition: AVAsset? = nil, context: JobContext) async throws {
        guard let session = AVAssetExportSession(asset: composition ?? asset, presetName: preset) else {
            throw RingoError.providerFailed(provider: "AVFoundation", message: "preset not available")
        }
        session.outputURL = out
        session.outputFileType = type
        if let range { session.timeRange = range }
        if let metadata { session.metadata = metadata }
        if filterForSharing { session.metadataItemFilter = .forSharing() }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in session.exportAsynchronously { c.resume() } }
        guard session.status == .completed else {
            throw RingoError.providerFailed(provider: "AVFoundation", message: session.error?.localizedDescription ?? "export failed")
        }
    }

    // MARK: Extract audio / mute

    static func extractAudio(_ input: InputFile, context: JobContext) async throws -> ProviderOutcome {
        if hasFFmpeg {
            let probe = try await ffmpeg.probe(input.url.path)
            guard probe.hasAudio else { throw RingoError.noAudioTrack(input.originalPath) }
            let copy = probe.audioCodec == "aac" || probe.audioCodec == "alac"
            let out = context.outputURL(ext: "m4a")
            try await runFFmpeg(["-i", "file:" + input.url.path, "-map", "0:a:0", "-vn"] + (copy ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "256k"]),
                                input: input, out: out, context: context, duration: probe.duration)
            var o = ProviderOutcome.single(out, "m4a")
            o.fidelity = copy ? .lossless : .lossy
            o.details["mode"] = copy ? "audio stream copied" : "re-encoded to AAC 256 kbps"
            return o
        }
        let asset = AVURLAsset(url: input.url)
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw RingoError.noAudioTrack(input.originalPath) }
        let out = context.outputURL(ext: "m4a")
        try await export(asset, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: out, context: context)
        return .single(out, "m4a")
    }

    static func mute(_ input: InputFile, context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        let out = context.outputURL(ext: ext(format))
        if hasFFmpeg {
            try await runFFmpeg(["-i", "file:" + input.url.path, "-map", "0", "-map", "-0:a", "-c", "copy"], input: input, out: out, context: context)
            var o = ProviderOutcome.single(out, format); o.fidelity = .lossless
            return o
        }
        let asset = AVURLAsset(url: input.url)
        let comp = AVMutableComposition()
        let duration = try await asset.load(.duration)
        for track in try await asset.loadTracks(withMediaType: .video) {
            let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try t?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
            t?.preferredTransform = try await track.load(.preferredTransform)
        }
        try await export(asset, preset: AVAssetExportPresetPassthrough, type: format == "mp4" ? .mp4 : .mov, to: out, composition: comp, context: context)
        var o = ProviderOutcome.single(out, format); o.fidelity = .lossless
        return o
    }

    // MARK: Crop (video)

    static func crop(_ input: InputFile, spec: CropSpec, context: JobContext) async throws -> ProviderOutcome {
        guard hasFFmpeg else { throw RingoError.providerMissing(provider: "FFmpeg", hint: "Video crop needs FFmpeg (`brew install ffmpeg`).") }
        let probe = try await ffmpeg.probe(input.url.path)
        guard let v = probe.streams.first(where: { $0["codec_type"] == "video" }), var w = Int(v["width"] ?? ""), var h = Int(v["height"] ?? "") else {
            throw RingoError.inputUnreadable(input.originalPath, reason: "no video stream")
        }
        if let rot = Int(v["rotation"] ?? "0"), abs(rot) % 180 == 90 { swap(&w, &h) }
        var rect = try ImageTools.cropRect(width: w, height: h, spec: spec)
        // Most codecs need even dimensions.
        rect = CGRect(x: floor(rect.minX / 2) * 2, y: floor(rect.minY / 2) * 2, width: floor(rect.width / 2) * 2, height: floor(rect.height / 2) * 2)
        let format = input.format!
        let out = context.outputURL(ext: ext(format))
        let codec: [String]
        switch format.rawValue {
        case "webm": codec = ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-c:a", "copy"]
        case "wmv": codec = ["-c:v", "wmv2", "-q:v", "3", "-c:a", "copy"]
        default: codec = ["-c:v", ffmpeg.h264Encoder ?? "h264_videotoolbox"] + (ffmpeg.h264Encoder == "libx264" ? ["-crf", "18", "-preset", "medium"] : ["-q:v", "70"]) + ["-c:a", "copy"]
        }
        try await runFFmpeg(["-i", "file:" + input.url.path, "-map", "0:v:0", "-map", "0:a?", "-vf",
                             "crop=\(Int(rect.width)):\(Int(rect.height)):\(Int(rect.minX)):\(Int(rect.minY))", "-pix_fmt", "yuv420p"] + codec,
                            input: input, out: out, context: context, duration: probe.duration)
        var o = ProviderOutcome.single(out, format)
        o.fidelity = .lossy
        o.details["rect"] = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"
        return o
    }

    // MARK: Compress

    static func compress(_ input: InputFile, spec: CompressSpec, context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        var details: [String: String] = ["preset": spec.preset.rawValue]
        var outFormat = format
        let out: URL
        if isVideo(format) {
            if hasFFmpeg {
                let probe = try await ffmpeg.probe(input.url.path)
                let enc = ffmpeg.encoders()
                let (crf, maxH): (Int, Int?) = {
                    switch spec.preset {
                    case .lossless: return (18, nil)
                    case .high: return (21, nil)
                    case .balanced: return (24, 1080)
                    case .small: return (28, 720)
                    case .tiny: return (32, 480)
                    }
                }()
                if !["mp4", "mov", "mkv"].contains(format.rawValue) { outFormat = "mp4" }
                out = context.outputURL(ext: ext(outFormat))
                var vf: [String] = []
                if let maxH { vf = ["-vf", "scale=-2:'min(\(maxH),ih)'"] }
                let hevc = spec.preset == .small || spec.preset == .tiny
                var codec: [String]
                if hevc && enc.contains("libx265") { codec = ["-c:v", "libx265", "-crf", String(crf), "-preset", "medium", "-tag:v", "hvc1"] }
                else if hevc && enc.contains("hevc_videotoolbox") { codec = ["-c:v", "hevc_videotoolbox", "-q:v", String(max(20, 80 - crf)), "-tag:v", "hvc1"] }
                else if enc.contains("libx264") { codec = ["-c:v", "libx264", "-crf", String(crf), "-preset", "slow"] }
                else { codec = ["-c:v", "h264_videotoolbox", "-q:v", String(max(20, 80 - crf))] }
                let audioK = spec.preset == .tiny ? 96 : spec.preset == .small ? 128 : 160
                try await runFFmpeg(["-i", "file:" + input.url.path, "-map", "0:v:0", "-map", "0:a?"] + vf + codec +
                                    ["-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "\(audioK)k", "-movflags", "+faststart"],
                                    input: input, out: out, context: context, duration: probe.duration)
                details["codec"] = codec[1]
            } else {
                guard avfVideo.contains(format) else {
                    throw RingoError.providerMissing(provider: "FFmpeg", hint: "Compressing \(format.rawValue.uppercased()) needs FFmpeg (`brew install ffmpeg`).")
                }
                let preset: String
                switch spec.preset {
                case .lossless, .high: preset = AVAssetExportPresetHEVCHighestQuality
                case .balanced: preset = AVAssetExportPresetHEVC1920x1080
                case .small: preset = AVAssetExportPreset1280x720
                case .tiny: preset = AVAssetExportPreset960x540
                }
                out = context.outputURL(ext: ext(format))
                try await export(AVURLAsset(url: input.url), preset: preset, type: format == "mov" ? .mov : .mp4, to: out, context: context)
                details["codec"] = preset
            }
        } else {
            guard hasFFmpeg else {
                guard ["wav", "aiff", "m4a", "mp3"].contains(format.rawValue) else {
                    throw RingoError.providerMissing(provider: "FFmpeg", hint: "Compressing \(format.rawValue.uppercased()) needs FFmpeg (`brew install ffmpeg`).")
                }
                outFormat = "m4a"
                out = context.outputURL(ext: "m4a")
                try await export(AVURLAsset(url: input.url), preset: AVAssetExportPresetAppleM4A, type: .m4a, to: out, context: context)
                return try finish(input, out: out, format: outFormat, details: details, lossy: true)
            }
            let kbps: Int = [.lossless: 320, .high: 256, .balanced: 192, .small: 128, .tiny: 96][spec.preset]!
            var args = ["-i", "file:" + input.url.path, "-map", "0:a:0", "-vn"]
            switch format.rawValue {
            case "wav", "aiff", "flac":
                if spec.preset == .lossless {
                    outFormat = "flac"; args += ["-c:a", "flac", "-compression_level", "12"]
                } else {
                    outFormat = "m4a"; args += ["-c:a", "aac", "-b:a", "\(kbps)k"]
                }
            case "mp3": args += ["-c:a", "libmp3lame", "-b:a", "\(kbps)k"]
            case "m4a": args += ["-c:a", "aac", "-b:a", "\(kbps)k"]
            case "opus": args += ["-c:a", "libopus", "-b:a", "\(max(kbps / 2, 32))k", "-f", "ogg"]
            case "ogg": args += ["-c:a", ffmpeg.oggEncoder?.codec ?? "libopus", "-b:a", "\(kbps / 2)k", "-f", "ogg"]
            case "wma": args += ["-c:a", "wmav2", "-b:a", "\(kbps)k"]
            default: throw RingoError.unsupportedTool(tool: "Compress", format: format.rawValue, reason: "unknown audio format")
            }
            out = context.outputURL(ext: ext(outFormat))
            try await runFFmpeg(args, input: input, out: out, context: context, duration: try await ffmpeg.probe(input.url.path).duration)
            details["bitrate"] = outFormat == "flac" ? "lossless" : "\(kbps) kbps"
            if outFormat != format { details["note"] = "\(format.rawValue.uppercased()) is uncompressed; saved as \(outFormat.rawValue.uppercased())" }
        }
        return try finish(input, out: out, format: outFormat, details: details, lossy: !(outFormat == "flac"))
    }

    static func finish(_ input: InputFile, out: URL, format: FormatID, details: [String: String], lossy: Bool) throws -> ProviderOutcome {
        var d = details
        let before = input.size, after = ImageTools.size(out)
        d["bytesBefore"] = String(before)
        d["bytesAfter"] = String(after)
        if after >= before {
            return ProviderOutcome(files: [], details: d, noChangeReason: "The result (\(after) bytes) was not smaller than the original (\(before) bytes); nothing was written.")
        }
        var o = ProviderOutcome.single(out, format)
        o.details = d
        o.fidelity = lossy ? .lossy : .lossless
        if format != input.format { o.warnings.append("Saved as \(format.rawValue.uppercased()) (\(input.format!.rawValue.uppercased()) cannot be compressed in place).") }
        return o
    }

    // MARK: Metadata

    static let ffmpegKeys: [String: String] = ["title": "title", "artist": "artist", "album": "album", "description": "comment", "comment": "comment",
                                                "copyright": "copyright", "year": "date", "date": "date", "genre": "genre", "keywords": "keywords", "composer": "composer"]

    static func setMetadata(_ input: InputFile, fields: [String: String], context: JobContext) async throws -> ProviderOutcome {
        guard hasFFmpeg else { throw RingoError.providerMissing(provider: "FFmpeg", hint: "Editing media tags needs FFmpeg (`brew install ffmpeg`).") }
        let format = input.format!
        var args = ["-i", "file:" + input.url.path, "-map", "0", "-c", "copy", "-map_metadata", "0"]
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) {
            guard let key = ffmpegKeys[k.lowercased()] else {
                throw RingoError.invalidArgument("Unsupported media tag '\(k)'. Editable: \(ffmpegKeys.keys.sorted().joined(separator: ", "))")
            }
            args += ["-metadata", "\(key)=\(v)"]
        }
        if ["mp4", "mov", "m4a"].contains(format.rawValue) { args += ["-movflags", "+use_metadata_tags"] }
        let out = context.outputURL(ext: ext(format))
        try await runFFmpeg(args, input: input, out: out, context: context)
        var o = ProviderOutcome.single(out, format); o.fidelity = .lossless
        return o
    }

    static func strip(_ input: InputFile, scope: StripScope, context: JobContext) async throws -> ProviderOutcome {
        let format = input.format!
        let out = context.outputURL(ext: ext(format))
        if hasFFmpeg {
            if scope == .location {
                try await runFFmpeg(["-i", "file:" + input.url.path, "-map", "0", "-c", "copy", "-map_metadata", "0",
                                     "-metadata", "location=", "-metadata", "location-eng=", "-metadata", "com.apple.quicktime.location.ISO6709="],
                                    input: input, out: out, context: context)
            } else {
                try await runFFmpeg(["-i", "file:" + input.url.path, "-map", "0", "-c", "copy", "-map_metadata", "-1", "-map_chapters", "-1", "-fflags", "+bitexact"],
                                    input: input, out: out, context: context)
            }
        } else {
            guard avfVideo.contains(format) || format == "m4a" else {
                throw RingoError.providerMissing(provider: "FFmpeg", hint: "Removing metadata from \(format.rawValue.uppercased()) needs FFmpeg (`brew install ffmpeg`).")
            }
            try await export(AVURLAsset(url: input.url), preset: AVAssetExportPresetPassthrough, type: format == "mov" ? .mov : format == "m4a" ? .m4a : .mp4,
                             to: out, metadata: scope == .all ? [] : nil, filterForSharing: true, context: context)
        }
        var o = ProviderOutcome.single(out, format); o.fidelity = .lossless
        o.details["removed"] = scope == .all ? "container and stream tags, chapters" : "location tags"
        return o
    }
}

/// Office Open XML document properties (DOCX/XLSX/PPTX): author, last-modified-by, company, comments …
enum OfficeTools {
    static let formats: Set<FormatID> = ["docx", "xlsx", "pptx"]

    static func strip(_ input: InputFile, context: JobContext) throws -> ProviderOutcome {
        let zip = try ZipReader(url: input.url)
        let w = ZipWriter()
        var removed: [String] = []
        for e in zip.entries {
            switch e.name {
            case "docProps/core.xml":
                w.add(e.name, """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>
                """)
                removed.append("core properties")
            case "docProps/app.xml":
                w.add(e.name, """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"/>
                """)
                removed.append("application properties")
            case "docProps/custom.xml":
                w.add(e.name, """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/custom-properties"/>
                """)
                removed.append("custom properties")
            default:
                w.add(e.name, try zip.read(e), store: e.name == "mimetype")
            }
        }
        let out = context.outputURL(ext: FormatCatalog.require(input.format!).primaryExtension)
        try w.finish().write(to: out)
        var o = ProviderOutcome.single(out, input.format!, warnings: ["Tracked changes and comments inside the document body are not removed."])
        o.details["removed"] = removed.joined(separator: ", ")
        return o
    }
}

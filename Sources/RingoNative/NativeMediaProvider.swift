@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import RingoCore
import RingoDomain

/// Audio/video through AVFoundation: hardware-accelerated, always available, limited to Apple codecs
/// and containers. FFmpeg (optional) covers the rest.
public final class NativeMediaProvider: ConversionProvider, @unchecked Sendable {
    public let id: ProviderID = "native.media"
    public let name = "AVFoundation (macOS)"
    public let defaultPriority = 15

    static let videoIn: [FormatID] = ["mov", "mp4"]
    static let audioIn: [FormatID] = ["m4a", "mp3", "wav", "aiff", "flac"]

    public init() {}

    public var edges: [EdgeSpec] {
        var out: [EdgeSpec] = []
        for v in Self.videoIn {
            for o in Self.videoIn where o != v {
                out.append(EdgeSpec(v, o, .remux, limitations: [
                    "Streams are copied when the codecs fit the target container; otherwise video is re-encoded to H.264/HEVC at the highest quality preset.",
                    "Subtitle and data tracks the target container cannot hold are dropped.",
                ], cost: 2))
            }
            out.append(EdgeSpec(v, "m4a", .lossy, limitations: ["Extracts the audio track as AAC."], cost: 2))
            out.append(EdgeSpec(v, "wav", .lossless, limitations: ["Extracts the audio track as PCM (decoded audio)."], cost: 2))
            out.append(EdgeSpec(v, "gif", .lossy, limitations: [
                "12 fps, at most 480 px wide, first 15 seconds by default (--fps, --max-width, --max-duration). Audio is dropped.",
            ], cost: 3, fallback: true))
        }
        for a in Self.audioIn {
            if a != "m4a" { out.append(EdgeSpec(a, "m4a", a == "mp3" ? .lossy : .lossy, limitations: ["AAC 256 kbps by default (--audio-bitrate)."], cost: 2)) }
            for pcm in ["wav", "aiff"] as [FormatID] where pcm != a {
                out.append(EdgeSpec(a, pcm, .lossless, limitations: ["Uncompressed PCM of the decoded audio; converting a lossy source does not restore quality."], cost: 1))
            }
        }
        return out
    }

    public func status() -> ProviderStatus {
        ProviderStatus(id: id, name: name, kind: .native, installed: true, license: "Apple system framework",
                       notes: ["Hardware-accelerated H.264/HEVC/AAC. Reads MOV, MP4, M4A, MP3, WAV, AIFF, FLAC."])
    }

    public func availability(of edge: EdgeSpec) -> (available: Bool, reason: String?) { (true, nil) }

    public func convert(_ request: ConversionRequest, context: JobContext) async throws -> ProviderOutcome {
        let asset = AVURLAsset(url: request.input.url)
        let out = context.outputURL(ext: request.targetExtension)
        let to = request.to
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        switch to.rawValue {
        case "mp4", "mov":
            guard !videoTracks.isEmpty || !audioTracks.isEmpty else { throw RingoError.inputUnreadable(request.input.url.lastPathComponent, reason: "no playable tracks") }
            let type: AVFileType = to == "mp4" ? .mp4 : .mov
            var preset = AVAssetExportPresetPassthrough
            var fidelity: Fidelity = .remux
            if !(await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: type)) {
                preset = AVAssetExportPresetHighestQuality
                fidelity = .lossy
            }
            try await export(asset, preset: preset, type: type, to: out, context: context)
            var o = ProviderOutcome.single(out, to, warnings: fidelity == .lossy ? ["Streams were re-encoded because their codecs do not fit \(to.rawValue.uppercased())."] : [])
            o.fidelity = fidelity
            o.details["mode"] = fidelity == .remux ? "stream copy" : "re-encode"
            return o
        case "m4a":
            guard !audioTracks.isEmpty else { throw RingoError.noAudioTrack(request.input.originalPath) }
            if request.options.audioBitrate == nil, await AVAssetExportSession.compatibility(ofExportPreset: AVAssetExportPresetAppleM4A, with: asset, outputFileType: .m4a) {
                try await export(asset, preset: AVAssetExportPresetAppleM4A, type: .m4a, to: out, context: context)
            } else {
                try await transcodeAudio(asset, to: out, fileType: .m4a, settings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: (request.options.audioBitrate ?? 256) * 1000,
                ], context: context)
            }
            return .single(out, to)
        case "wav", "aiff":
            guard !audioTracks.isEmpty else { throw RingoError.noAudioTrack(request.input.originalPath) }
            let bits = try await sourceBitDepth(audioTracks[0])
            try await transcodeAudio(asset, to: out, fileType: to == "wav" ? .wav : .aiff, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: bits, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: to == "aiff", AVLinearPCMIsNonInterleaved: false,
            ], context: context)
            var o = ProviderOutcome.single(out, to)
            o.details["bitDepth"] = String(bits)
            return o
        case "gif":
            guard let track = videoTracks.first else { throw RingoError.inputUnreadable(request.input.originalPath, reason: "no video track") }
            let warnings = try await makeGIF(asset, track: track, to: out, options: request.options, context: context)
            return .single(out, to, warnings: warnings)
        default:
            throw RingoError.unsupportedConversion(from: request.from.rawValue, to: to.rawValue, reason: "not an AVFoundation target")
        }
    }

    func export(_ asset: AVAsset, preset: String, type: AVFileType, to out: URL, context: JobContext) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw RingoError.providerFailed(provider: name, message: "export preset \(preset) is not available for this file")
        }
        session.outputURL = out
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = true
        let done = AtomicFlag()
        let poll = Task {
            while !done.value {
                context.progress(Double(session.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { done.set(); poll.cancel() }
        try await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { c.resume() }
            }
        } onCancel: {
            session.cancelExport()
        }
        switch session.status {
        case .completed: return
        case .cancelled: throw RingoError.cancelled
        default: throw RingoError.providerFailed(provider: name, message: session.error?.localizedDescription ?? "export failed")
        }
    }

    func sourceBitDepth(_ track: AVAssetTrack) async throws -> Int {
        let descs = try await track.load(.formatDescriptions)
        guard let d = descs.first, let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(d)?.pointee else { return 16 }
        if asbd.mFormatID == kAudioFormatLinearPCM && asbd.mBitsPerChannel > 0 { return min(max(Int(asbd.mBitsPerChannel), 16), 32) }
        // FLAC/ALAC keep their bit depth in format flags.
        if asbd.mFormatID == kAudioFormatFLAC || asbd.mFormatID == kAudioFormatAppleLossless {
            switch asbd.mFormatFlags {
            case 2: return 20
            case 3: return 24
            case 4: return 32
            default: return 16
            }
        }
        return 16
    }

    func transcodeAudio(_ asset: AVAsset, to out: URL, fileType: AVFileType, settings: [String: Any], context: JobContext) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw RingoError.noAudioTrack(out.lastPathComponent) }
        let descs = try await track.load(.formatDescriptions)
        let asbd = descs.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let rate = asbd?.mSampleRate ?? 44100
        let channels = Int(asbd?.mChannelsPerFrame ?? 2)
        let duration = try await asset.load(.duration).seconds

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(readerOutput)
        let writer = try AVAssetWriter(outputURL: out, fileType: fileType)
        var s = settings
        s[AVSampleRateKey] = rate
        s[AVNumberOfChannelsKey] = channels
        if channels > 2 && (s[AVFormatIDKey] as? AudioFormatID) == kAudioFormatMPEG4AAC {
            s[AVNumberOfChannelsKey] = 2
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: s)
        input.expectsMediaDataInRealTime = false
        writer.add(input)
        guard reader.startReading() else { throw RingoError.providerFailed(provider: name, message: reader.error?.localizedDescription ?? "read failed") }
        guard writer.startWriting() else { throw RingoError.providerFailed(provider: name, message: writer.error?.localizedDescription ?? "write failed") }
        writer.startSession(atSourceTime: .zero)
        let queue = DispatchQueue(label: "ringo.audio")
        let box = UncheckedBox((reader, readerOutput, writer, input))
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let (reader, readerOutput, writer, input) = box.value
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if Task.isCancelled { reader.cancelReading() }
                    if let buf = readerOutput.copyNextSampleBuffer() {
                        if duration > 0 { context.progress(min(CMSampleBufferGetPresentationTimeStamp(buf).seconds / duration, 0.99)) }
                        if !input.append(buf) {
                            input.markAsFinished()
                            reader.cancelReading()
                            c.resume(throwing: RingoError.providerFailed(provider: "AVFoundation", message: writer.error?.localizedDescription ?? "append failed"))
                            return
                        }
                    } else {
                        input.markAsFinished()
                        if reader.status == .failed {
                            c.resume(throwing: RingoError.providerFailed(provider: "AVFoundation", message: reader.error?.localizedDescription ?? "read failed"))
                        } else {
                            writer.finishWriting { c.resume() }
                        }
                        return
                    }
                }
            }
        }
        if writer.status != .completed {
            throw RingoError.providerFailed(provider: name, message: writer.error?.localizedDescription ?? "audio export failed")
        }
    }

    func makeGIF(_ asset: AVAsset, track: AVAssetTrack, to out: URL, options: ConversionOptions, context: JobContext) async throws -> [String] {
        let duration = try await asset.load(.duration).seconds
        let fps = min(max(options.fps ?? 12, 1), 30)
        let maxDuration = options.maxDuration ?? 15
        let length = min(duration, maxDuration)
        var warnings: [String] = []
        if duration > maxDuration { warnings.append("Only the first \(Int(maxDuration)) s were exported (--max-duration).") }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        let maxW = CGFloat(options.maxWidth ?? 480)
        gen.maximumSize = CGSize(width: maxW, height: maxW * 4)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5 / fps, preferredTimescale: 600)
        let frameCount = max(1, Int(length * fps))
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "com.compuserve.gif" as CFString, frameCount, nil) else {
            throw RingoError.outputWriteFailed(out.path, reason: "could not create GIF")
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps]] as CFDictionary
        for i in 0..<frameCount {
            try Task.checkCancellation()
            let t = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            let (img, _) = try await gen.image(at: t)
            CGImageDestinationAddImage(dest, img, frameProps)
            context.progress(Double(i + 1) / Double(frameCount))
        }
        guard CGImageDestinationFinalize(dest) else { throw RingoError.outputWriteFailed(out.path, reason: "GIF encode failed") }
        return warnings
    }
}

struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ v: T) { value = v }
}

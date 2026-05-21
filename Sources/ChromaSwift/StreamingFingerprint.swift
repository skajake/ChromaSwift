// SPDX-License-Identifier: MIT
//
// Streaming wrapper around the libchromaprint C API. Lets callers feed
// interleaved Int16 PCM in chunks and snapshot the raw uint32 fingerprint.
//
// A single instance can be snapshotted exactly once (chromaprint_finish
// permanently finalizes the context). The intended pattern is to maintain
// a rolling raw-PCM ring buffer on the caller side and spin up a fresh
// StreamingFingerprint each time you need to search for a needle.

import Foundation
import CChromaprint

public final class StreamingFingerprint {
    public enum Error: Swift.Error {
        case startFailed
        case finishFailed
        case readFailed
    }

    public let algorithm: AudioFingerprint.Algorithm
    public let sampleRate: Int32
    public let channels: Int32

    private let context: OpaquePointer
    private var finished = false

    public init(
        algorithm: AudioFingerprint.Algorithm = .test2,
        sampleRate: Int32,
        channels: Int32
    ) throws {
        guard let ctx = chromaprint_new(algorithm.rawValue) else {
            throw Error.startFailed
        }
        if chromaprint_start(ctx, sampleRate, channels) != 1 {
            chromaprint_free(ctx)
            throw Error.startFailed
        }
        self.context = ctx
        self.algorithm = algorithm
        self.sampleRate = sampleRate
        self.channels = channels
    }

    deinit {
        chromaprint_free(context)
    }

    /// Feed interleaved Int16 PCM. `count` is total samples (frames × channels).
    public func feed(_ samples: UnsafePointer<Int16>, count: Int) {
        guard !finished else { return }
        _ = chromaprint_feed(context, samples, Int32(count))
    }

    /// Finalize and return the raw fingerprint frames. May be called exactly
    /// once per instance; subsequent calls return the same cached value.
    public func snapshot() throws -> [UInt32] {
        if !finished {
            if chromaprint_finish(context) != 1 {
                throw Error.finishFailed
            }
            finished = true
        }
        var ptr: UnsafeMutablePointer<UInt32>? = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
        defer { ptr?.deallocate() }
        var size: Int32 = 0
        if chromaprint_get_raw_fingerprint(context, &ptr, &size) != 1 {
            throw Error.readFailed
        }
        guard let buffer = ptr, size > 0 else { return [] }
        return [UInt32](UnsafeBufferPointer(start: buffer, count: Int(size)))
    }

    /// Number of PCM samples (per channel) that compress into one fingerprint frame.
    /// Useful for converting between PCM-sample offsets and fingerprint-frame offsets.
    public var samplesPerFingerprintFrame: Int32 {
        return chromaprint_get_item_duration(context)
    }
}

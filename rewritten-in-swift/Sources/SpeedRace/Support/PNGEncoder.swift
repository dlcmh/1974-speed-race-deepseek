import Foundation

// Speed Race (1974) — Swift + Metal port.
//
// Minimal PNG encoder for headless rendering verification.
//
// The Rust game saves screenshots with macroquad's `export_png`. The port needs
// the same capability without an image library (the "no asset pipeline" rule
// applies to tooling too: no third-party dependencies), and the same bytes are
// used by `speed-race --render` to write the doc screenshots that are compared
// against the canonical Rust captures in ../docs/.
//
// Implementation notes:
//   * 8-bit RGBA, no interlacing, a single IDAT chunk.
//   * Filter type 0 (None) on every scanline. This keeps the encoder tiny and
//     byte-exact; PNG readers do not require better filters.
//   * CRC-32 and Adler-32 are table-driven and pure Swift (no zlib linking).

public enum PNGEncoder {
    /// Encodes straight (non-premultiplied) RGBA bytes, top row first.
    public static func encodeRGBA(width: Int, height: Int, pixels: [UInt8]) -> Data {
        precondition(pixels.count == width * height * 4, "pixel buffer size must match dimensions")

        // Raw scanlines with a leading filter byte.
        var raw = [UInt8]()
        raw.reserveCapacity(height * (width * 4 + 1))
        for row in 0..<height {
            raw.append(0)  // filter: None
            let start = row * width * 4
            raw.append(contentsOf: pixels[start..<(start + width * 4)])
        }

        var png = [UInt8]()
        png.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var header = Data()
        appendBigEndian(UInt32(width), to: &header)
        appendBigEndian(UInt32(height), to: &header)
        // bit depth 8, colour type 6 (RGBA), compression 0, filter 0, interlace 0.
        header.append(contentsOf: [8, 6, 0, 0, 0])
        appendChunk(type: "IHDR", payload: header, to: &png)

        var compressed = Data([0x78, 0x01])  // zlib: deflate, 32K window, no preset dict
        compressed.append(storedDeflate(raw))
        appendBigEndian(adler32(raw), to: &compressed)
        appendChunk(type: "IDAT", payload: compressed, to: &png)

        appendChunk(type: "IEND", payload: Data(), to: &png)
        return Data(png)
    }

    // MARK: - zlib

    /// Deflate in "stored" (uncompressed) blocks: a valid zlib stream with zero
    /// compression effort. PNG is a verification artefact here, not a shipped
    /// asset, and correctness matters more than size.
    private static func storedDeflate(_ input: [UInt8]) -> Data {
        var out = Data()
        let maxBlock = 65_535
        var offset = 0
        repeat {
            let count = min(maxBlock, input.count - offset)
            let isFinal = offset + count >= input.count
            out.append(isFinal ? 1 : 0)
            out.append(UInt8(count & 0xFF))
            out.append(UInt8((count >> 8) & 0xFF))
            let inverse = ~count & 0xFFFF
            out.append(UInt8(inverse & 0xFF))
            out.append(UInt8((inverse >> 8) & 0xFF))
            out.append(contentsOf: input[offset..<(offset + count)])
            offset += count
        } while offset < input.count
        return out
    }

    private static func appendBigEndian(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    // MARK: - Chunks

    private static func appendChunk(type: String, payload: Data, to png: inout [UInt8]) {
        var body = Data(type.utf8)
        body.append(payload)
        var length = Data()
        appendBigEndian(UInt32(payload.count), to: &length)
        png.append(contentsOf: length)
        png.append(contentsOf: body)
        var crc = Data()
        appendBigEndian(crc32(body), to: &crc)
        png.append(contentsOf: crc)
    }

    // MARK: - Checksums

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var c = UInt32(index)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return (b << 16) | a
    }
}

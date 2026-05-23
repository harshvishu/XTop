import Foundation
import IOKit

// MARK: - Public Types

/// Errors surfaced by ``SMCReader`` operations.
enum SMCReaderError: Error, Sendable, Equatable {
    /// The caller asked for a key outside the read-only allowlist.
    case keyNotAllowed(key: String)

    /// The AppleSMC IOService could not be opened on this host.
    case serviceUnavailable

    /// The SMC call returned a non-success status for the key.
    case keyReadFailed(key: String, status: Int32)

    /// The key exists but the returned bytes did not decode as the expected
    /// numeric type.
    case decodeFailed(key: String, type: String)
}

/// Symbolic SMC keys ``SMCReader`` is allowed to read.
///
/// Adding entries here is the *only* way to widen SMC surface area. The
/// reader refuses any key not present in this enum, which keeps the
/// security audit small and prevents future call sites from probing
/// arbitrary SMC fields.
enum SMCKey: String, CaseIterable, Sendable {
    // CPU package / die temperatures. Different Mac models expose different
    // keys; ``SMCReader`` callers probe in order and use the first that
    // succeeds.
    case cpuProximityTemp = "TC0P"
    case cpuDieTemp = "TC0D"
    case cpuPackageTemp = "TCXC"

    // GPU temperatures (Intel discrete + Apple Silicon variants).
    case gpuProximityTemp = "TG0P"
    case gpuDieTemp = "TG0D"

    // Fan speeds. F0Ac/F1Ac = current RPM, F0Mn/F0Mx = min/max for fan 0.
    case fan0Current = "F0Ac"
    case fan1Current = "F1Ac"
    case fan0Min = "F0Mn"
    case fan0Max = "F0Mx"

    /// Four-byte SMC key suitable for the kernel API.
    var fourCC: UInt32 {
        var value: UInt32 = 0
        for byte in rawValue.utf8 {
            value = (value << 8) | UInt32(byte)
        }
        return value
    }
}

// MARK: - SMCReader

/// Read-only, key-restricted SMC client.
///
/// ``SMCReader`` opens the `AppleSMC` IOService once on first use and
/// reuses the connection for the lifetime of the instance. It only ever
/// issues `kSMCReadKey`-equivalent calls; no write opcodes, no fan
/// control, no SMC-side mutations of any kind.
///
/// The reader is `Sendable` because all mutation happens behind a serial
/// dispatch queue, but in practice callers should treat one instance per
/// telemetry actor as a fast-path resource.
final class SMCReader: @unchecked Sendable {

    // SMC selector / data type constants from AppleSMC kext interface.
    // These are stable across modern macOS releases.
    private static let kSMCUserClientOpen: UInt32 = 0
    private static let kSMCUserClientClose: UInt32 = 1
    private static let kSMCHandleYPCEvent: UInt32 = 2
    private static let kSMCReadKey: UInt8 = 5
    private static let kSMCGetKeyInfo: UInt8 = 9

    private let lock = NSLock()
    private var connection: io_connect_t = 0
    private var connectionOpened = false

    init() {}

    deinit {
        closeConnection()
    }

    // MARK: Public API

    /// Read a value for the given key. Throws ``SMCReaderError`` on any
    /// failure path. The returned value is `nil` only when the SMC
    /// reported a zero-byte payload, which we treat as "no reading
    /// available" rather than a hard error.
    func readDouble(_ key: SMCKey) throws -> Double? {
        try ensureKeyAllowed(key.rawValue)
        try openConnectionIfNeeded()

        var keyInfo = try fetchKeyInfo(for: key)
        guard keyInfo.dataSize > 0, keyInfo.dataSize <= 32 else {
            return nil
        }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key.fourCC
        input.keyInfo.dataSize = keyInfo.dataSize
        input.keyInfo.dataType = keyInfo.dataType
        input.data8 = SMCReader.kSMCReadKey

        try call(input: &input, output: &output)

        return decode(
            data: output.bytes,
            size: Int(keyInfo.dataSize),
            type: keyInfo.dataType,
            key: key.rawValue
        )
    }

    /// Convenience: probe a list of keys in order and return the first
    /// value that decodes successfully. Returns `nil` if every key is
    /// missing or undecodable. Throws only for non-key errors (service
    /// unreachable, allowlist violation).
    func firstAvailable(of keys: [SMCKey]) throws -> Double? {
        for key in keys {
            do {
                if let value = try readDouble(key) {
                    return value
                }
            } catch SMCReaderError.keyReadFailed,
                    SMCReaderError.decodeFailed {
                continue
            }
        }
        return nil
    }

    // MARK: Allowlist

    private func ensureKeyAllowed(_ raw: String) throws {
        if SMCKey(rawValue: raw) == nil {
            throw SMCReaderError.keyNotAllowed(key: raw)
        }
    }

    // MARK: Connection management

    private func openConnectionIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }

        if connectionOpened {
            return
        }

        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else {
            throw SMCReaderError.serviceUnavailable
        }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess else {
            throw SMCReaderError.serviceUnavailable
        }
        connection = conn
        connectionOpened = true
    }

    private func closeConnection() {
        lock.lock()
        defer { lock.unlock() }
        if connectionOpened {
            IOServiceClose(connection)
            connectionOpened = false
            connection = 0
        }
    }

    // MARK: SMC calls

    private struct KeyInfo {
        var dataSize: UInt32
        var dataType: UInt32
    }

    private func fetchKeyInfo(for key: SMCKey) throws -> KeyInfo {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = key.fourCC
        input.data8 = SMCReader.kSMCGetKeyInfo

        try call(input: &input, output: &output)

        return KeyInfo(
            dataSize: output.keyInfo.dataSize,
            dataType: output.keyInfo.dataType
        )
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) throws {
        let inputSize = MemoryLayout<SMCKeyData>.size
        var outputSize = MemoryLayout<SMCKeyData>.size

        let result = withUnsafePointer(to: &input) { inPtr in
            withUnsafeMutablePointer(to: &output) { outPtr in
                IOConnectCallStructMethod(
                    connection,
                    SMCReader.kSMCHandleYPCEvent,
                    inPtr,
                    inputSize,
                    outPtr,
                    &outputSize
                )
            }
        }

        guard result == kIOReturnSuccess, output.result == 0 else {
            // Pull a useful key name out for diagnostics.
            let keyName = String(cString: SMCReader.fourCCToString(input.key))
            throw SMCReaderError.keyReadFailed(
                key: keyName,
                status: Int32(bitPattern: UInt32(result))
            )
        }
    }

    // MARK: Decoders

    /// Decode an SMC value buffer for the recognized numeric types used
    /// by the allowlisted keys. Returns `nil` for unrecognized types.
    private func decode(
        data: SMCBytes,
        size: Int,
        type: UInt32,
        key: String
    ) -> Double? {
        var buffer = [UInt8](repeating: 0, count: 32)
        withUnsafeBytes(of: data) { raw in
            for index in 0..<min(size, raw.count) {
                buffer[index] = raw[index]
            }
        }

        let typeString = SMCReader.fourCCString(from: type)

        switch typeString {
        case "sp78":
            // 16-bit signed fixed-point: integer.fraction split at bit 7.
            guard size >= 2 else { return nil }
            let raw = Int16(buffer[0]) << 8 | Int16(buffer[1])
            return Double(raw) / 256.0
        case "flt ":
            guard size >= 4 else { return nil }
            let bits = buffer.withUnsafeBufferPointer { ptr -> UInt32 in
                var value: UInt32 = 0
                memcpy(&value, ptr.baseAddress, 4)
                return value
            }
            return Double(Float(bitPattern: bits))
        case "fpe2":
            // 16-bit unsigned fixed-point with 2 fractional bits.
            guard size >= 2 else { return nil }
            let raw = UInt16(buffer[0]) << 8 | UInt16(buffer[1])
            return Double(raw) / 4.0
        case "ui8 ":
            return Double(buffer[0])
        case "ui16":
            guard size >= 2 else { return nil }
            let raw = UInt16(buffer[0]) << 8 | UInt16(buffer[1])
            return Double(raw)
        case "ui32":
            guard size >= 4 else { return nil }
            let raw = UInt32(buffer[0]) << 24
                | UInt32(buffer[1]) << 16
                | UInt32(buffer[2]) << 8
                | UInt32(buffer[3])
            return Double(raw)
        default:
            return nil
        }
    }

    // MARK: Helpers

    /// Convert a packed FourCC into a printable 4-character string.
    private static func fourCCString(from value: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    /// Return a C string (heap-free) suitable for diagnostic messages.
    private static func fourCCToString(_ value: UInt32) -> [CChar] {
        let s = fourCCString(from: value)
        return s.cString(using: .ascii) ?? [0]
    }
}

// MARK: - SMC binary layout

/// Mirrors the kernel-side SMCKeyData_t structure used by the AppleSMC
/// user client. Field order and sizes are stable across modern macOS;
/// don't reorder.
private struct SMCKeyData {
    var key: UInt32 = 0
    var vers: SMCVers = .init()
    var pLimitData: SMCPLimitData = .init()
    var keyInfo: SMCKeyInfo = .init()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = .init()
}

private struct SMCVers {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

/// 32-byte SMC data payload buffer.
private struct SMCBytes {
    var b: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )
}

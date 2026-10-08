import Foundation

/// Zipro treadmill BLE protocol (advertises as `RZ_TreadMil`).
///
/// Host -> treadmill (write FFF2, with response): `FB len payload… sum FC`
/// Treadmill -> host (notify FFF1):               `FD len payload… sum FE`
/// `len` counts itself, the payload and the checksum; `sum = (len + Σpayload) & 0xFF`.
public enum ZiproProtocol {
    /// Speed limits reported by the treadmill in its `A0 02` reply (`0a`, `50`).
    public static let speedRange: ClosedRange<Double> = 1.0...8.0

    public static func frame(_ payload: [UInt8]) -> Data {
        let length = UInt8(payload.count + 2)
        let sum = payload.reduce(length, &+)
        return Data([0xFB, length] + payload + [sum, 0xFC])
    }

    public static let start = frame([0xA2, 0x01, 0x01])
    public static let stop = frame([0xA2, 0x04, 0x01])

    /// Handshake from qdomyos-zwift; makes the treadmill answer `A0` info queries.
    public static let initSequence: [Data] =
        (0...3).map { frame([0xA0, UInt8($0), 0x01]) } + [
            frame([0xA1, 0x00, 0x01]),
            frame([0xA1, 0x00, 0x00, 0x00]),
            frame([0xA1, 0x00, 0x01]),
        ]

    /// `A1 02 <force> <speed×10> <incline>`; clamps speed to `speedRange`.
    public static func setSpeed(_ kmh: Double, incline: UInt8 = 0) -> Data {
        let clamped = min(max(kmh, speedRange.lowerBound), speedRange.upperBound)
        return frame([0xA1, 0x02, 0x01, UInt8((clamped * 10).rounded()), incline])
    }

    /// Parses an `A1` status frame: the 6/7-byte idle/ack beacon or the 18-byte running status.
    /// Returns nil for other messages (e.g. `A0` info replies) and corrupt frames.
    public static func parse(_ data: Data) -> TreadmillStatus? {
        let b = [UInt8](data)
        guard b.count >= 6, b.first == 0xFD, b.last == 0xFE, Int(b[1]) == b.count - 2,
              b[1..<(b.count - 2)].reduce(0, &+) == b[b.count - 2],
              b[2] == 0xA1
        else { return nil }

        let state = TreadmillState(byte: b[3])
        guard b.count == 18 else { return TreadmillStatus(state: state) }
        return TreadmillStatus(
            state: state,
            targetSpeed: Double(b[4]) / 10,
            speed: Double(b[5]) / 10,
            incline: Int(b[6]),
            elapsed: Int(b[10]),
            heartRate: Int(b[15])
        )
    }
}

public enum TreadmillState: Equatable, Sendable {
    case idle, countdown, running, stopping, stopped
    /// Console asleep after 10 min idle (6-byte beacon `fd 04 a1 08 ad fe`). Only the remote wakes it:
    /// it ignores every BLE command except stop, and BLE keepalives don't reset the timer.
    case sleeping
    case unknown(UInt8)

    init(byte: UInt8) {
        switch byte {
        case 0x00: self = .idle
        case 0x01: self = .countdown
        case 0x02: self = .running
        case 0x04: self = .stopping
        case 0x05: self = .stopped
        case 0x08: self = .sleeping
        default: self = .unknown(byte)
        }
    }
}

public struct TreadmillStatus: Equatable, Sendable {
    public var state: TreadmillState
    public var targetSpeed: Double = 0
    public var speed: Double = 0
    public var incline: Int = 0
    /// Seconds running; during `.countdown` it counts down to the start.
    public var elapsed: Int = 0
    public var heartRate: Int = 0
}

import Foundation
import Testing
@testable import ZiproKit

private func hex(_ s: String) -> Data {
    Data(s.split(separator: " ").map { UInt8($0, radix: 16)! })
}

private func hexString(_ d: Data) -> String {
    d.map { String(format: "%02x", $0) }.joined(separator: " ")
}

// Expected bytes are frames captured from / verified against the real treadmill.
@Suite struct FrameTests {
    @Test func commands() {
        #expect(hexString(ZiproProtocol.start) == "fb 05 a2 01 01 a9 fc")
        #expect(hexString(ZiproProtocol.stop) == "fb 05 a2 04 01 ac fc")
        #expect(hexString(ZiproProtocol.setSpeed(2.0)) == "fb 07 a1 02 01 14 00 bf fc")
        #expect(hexString(ZiproProtocol.setSpeed(2.0, incline: 1)) == "fb 07 a1 02 01 14 01 c0 fc")
    }

    @Test func initSequence() {
        #expect(ZiproProtocol.initSequence.map(hexString) == [
            "fb 05 a0 00 01 a6 fc", "fb 05 a0 01 01 a7 fc", "fb 05 a0 02 01 a8 fc", "fb 05 a0 03 01 a9 fc",
            "fb 05 a1 00 01 a7 fc", "fb 06 a1 00 00 00 a7 fc", "fb 05 a1 00 01 a7 fc",
        ])
    }

    @Test func speedIsClampedAndRounded() {
        #expect(hexString(ZiproProtocol.setSpeed(12)) == hexString(ZiproProtocol.setSpeed(8.0)))
        #expect(hexString(ZiproProtocol.setSpeed(0.2)) == hexString(ZiproProtocol.setSpeed(1.0)))
        #expect(hexString(ZiproProtocol.setSpeed(3.04999)) == hexString(ZiproProtocol.setSpeed(3.0)))
    }
}

@Suite struct ParseTests {
    @Test func idleBeacon() {
        #expect(ZiproProtocol.parse(hex("fd 05 a1 00 00 a6 fe")) == TreadmillStatus(state: .idle))
    }

    @Test func sleepBeacon() {
        #expect(ZiproProtocol.parse(hex("fd 04 a1 08 ad fe")) == TreadmillStatus(state: .sleeping))
    }

    @Test func startAck() {
        #expect(ZiproProtocol.parse(hex("fd 05 a1 01 05 ac fe"))?.state == .countdown)
    }

    @Test func countdown() {
        let s = ZiproProtocol.parse(hex("fd 10 a1 01 0a 05 00 00 00 00 03 00 00 00 00 00 c4 fe"))
        #expect(s?.state == .countdown)
        #expect(s?.elapsed == 3)
    }

    @Test func running() {
        let s = ZiproProtocol.parse(hex("fd 10 a1 02 14 0d 00 00 00 00 17 00 00 00 04 00 ef fe"))
        #expect(s == TreadmillStatus(state: .running, targetSpeed: 2.0, speed: 1.3, incline: 0, elapsed: 23, heartRate: 0))
    }

    @Test func stoppingAndStopped() {
        #expect(ZiproProtocol.parse(hex("fd 10 a1 04 09 09 00 00 00 00 06 00 00 00 01 00 ce fe"))?.state == .stopping)
        #expect(ZiproProtocol.parse(hex("fd 10 a1 05 00 00 00 00 00 00 06 00 00 00 01 00 bd fe"))?.state == .stopped)
    }

    @Test func rejectsBadFrames() {
        #expect(ZiproProtocol.parse(hex("fd 05 a1 00 00 a7 fe")) == nil)  // checksum
        #expect(ZiproProtocol.parse(hex("fd 08 a0 00 f0 01 00 01 9a fe")) == nil)  // A0 info reply
        #expect(ZiproProtocol.parse(hex("fd 05 a1 00")) == nil)  // truncated
    }
}

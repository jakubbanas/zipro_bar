@preconcurrency import CoreBluetooth
import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.kuba.ziprobar", category: "ble")

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}

/// Finds, connects to and controls a Zipro treadmill. Reconnects automatically.
@MainActor
@Observable
public final class Treadmill: NSObject {
    public enum Connection: Equatable, Sendable {
        case bluetoothUnavailable, scanning, connecting, connected
    }

    public private(set) var connection: Connection = .bluetoothUnavailable
    public private(set) var status: TreadmillStatus?

    nonisolated private static let namePrefix = "RZ_TREADMIL"
    nonisolated private static let serviceUUID = CBUUID(string: "FFF0")
    nonisolated private static let notifyUUID = CBUUID(string: "FFF1")
    nonisolated private static let writeUUID = CBUUID(string: "FFF2")

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var writeCharacteristic: CBCharacteristic?
    // FFF2 only accepts write-with-response, so writes go out one at a time.
    @ObservationIgnored private var pendingWrites: [Data] = []
    @ObservationIgnored private var writeInFlight = false

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    public func start() { send(ZiproProtocol.start) }

    public func stop() {
        // Stop is safety-critical: send it ahead of anything queued, twice.
        pendingWrites.removeAll()
        send(ZiproProtocol.stop)
        send(ZiproProtocol.stop)
    }

    public func setSpeed(_ kmh: Double) {
        send(ZiproProtocol.setSpeed(kmh, incline: UInt8(clamping: status?.incline ?? 0)))
    }

    /// Waits until all queued writes are acknowledged, or `timeout` passes.
    public func flush(timeout: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now + timeout
        while (writeInFlight || !pendingWrites.isEmpty) && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func send(_ data: Data) {
        guard writeCharacteristic != nil else { return }
        pendingWrites.append(data)
        writeNext()
    }

    private func writeNext() {
        guard !writeInFlight, let peripheral, let writeCharacteristic, !pendingWrites.isEmpty else { return }
        writeInFlight = true
        log.debug("tx \(self.pendingWrites[0].hex, privacy: .public)")
        peripheral.writeValue(pendingWrites.removeFirst(), for: writeCharacteristic, type: .withResponse)
    }

    private func scan() {
        guard central.state == .poweredOn else {
            connection = .bluetoothUnavailable
            return
        }
        connection = .scanning
        // The treadmill doesn't advertise FFF0, so match on its name.
        central.scanForPeripherals(withServices: nil)
    }

    private func reset() {
        peripheral = nil
        writeCharacteristic = nil
        pendingWrites.removeAll()
        writeInFlight = false
        status = nil
    }
}

extension Treadmill: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            if central.state == .poweredOn {
                scan()
            } else {
                reset()
                connection = .bluetoothUnavailable
            }
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name.uppercased().hasPrefix(Treadmill.namePrefix) else { return }
        MainActor.assumeIsolated {
            guard self.peripheral == nil else { return }
            central.stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            connection = .connecting
            log.info("connecting to \(name, privacy: .public)")
            central.connect(peripheral)
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("connected")
        peripheral.discoverServices([Treadmill.serviceUUID])
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        log.error("connect failed: \(String(describing: error), privacy: .public)")
        MainActor.assumeIsolated {
            reset()
            scan()
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        log.info("disconnected: \(String(describing: error), privacy: .public)")
        MainActor.assumeIsolated {
            reset()
            scan()
        }
    }
}

extension Treadmill: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Treadmill.serviceUUID }) else {
            log.error("FFF0 not found: \(String(describing: error), privacy: .public)")
            return
        }
        peripheral.discoverCharacteristics([Treadmill.notifyUUID, Treadmill.writeUUID], for: service)
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        let characteristics = service.characteristics ?? []
        guard let notify = characteristics.first(where: { $0.uuid == Treadmill.notifyUUID }),
              let write = characteristics.first(where: { $0.uuid == Treadmill.writeUUID })
        else {
            log.error("FFF1/FFF2 not found: \(String(describing: error), privacy: .public)")
            return
        }
        log.info("characteristics found, subscribing")
        peripheral.setNotifyValue(true, for: notify)
        MainActor.assumeIsolated {
            writeCharacteristic = write
            // No init handshake: control works without it, and after it the treadmill
            // switches to an unexplained state 0x08 beacon (`fd 04 a1 08 ad fe`).
            connection = .connected
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        guard let data = characteristic.value else { return }
        log.debug("rx \(data.hex, privacy: .public)")
        guard let parsed = ZiproProtocol.parse(data) else { return }
        MainActor.assumeIsolated {
            if parsed.state != status?.state {
                log.info("state \(String(describing: parsed.state), privacy: .public)")
            }
            status = parsed
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        if let error { log.error("write failed: \(error, privacy: .public)") }
        MainActor.assumeIsolated {
            writeInFlight = false
            writeNext()
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?
    ) {
        log.info("notifying=\(characteristic.isNotifying) error=\(String(describing: error), privacy: .public)")
    }
}

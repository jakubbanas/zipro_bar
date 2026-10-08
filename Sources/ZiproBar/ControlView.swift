import ServiceManagement
import SwiftUI
import ZiproKit

struct ControlView: View {
    let treadmill: Treadmill

    @State private var target = ZiproProtocol.speedRange.lowerBound
    @State private var dragging = false
    @State private var pendingSend: Task<Void, Never>?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var state: TreadmillState? { treadmill.status?.state }
    private var connected: Bool { treadmill.connection == .connected }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).font(.headline)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(treadmill.status?.speed ?? 0, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("km/h").foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                // No `step:` — on macOS it draws a tick per step; setSpeed rounds to 0.1 anyway.
                Slider(value: $target, in: ZiproProtocol.speedRange) {
                    Text("Speed")
                } minimumValueLabel: {
                    Text(ZiproProtocol.speedRange.lowerBound, format: .number)
                } maximumValueLabel: {
                    Text(ZiproProtocol.speedRange.upperBound, format: .number)
                } onEditingChanged: { editing in
                    dragging = editing
                    if !editing { sendSpeed(after: .zero) }
                }
                .labelsHidden()
                .disabled(state != .running)

                Text("Target \(target, format: .number.precision(.fractionLength(1))) km/h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Start") { treadmill.start() }
                    .disabled(!connected || !(state == .idle || state == .stopped))
                Button("Stop", role: .destructive) { treadmill.stop() }
                    .disabled(!connected)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)

            Divider()

            Toggle("Open at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }

            Button("Quit ZiproBar") { quit() }
                .buttonStyle(.borderless)
        }
        .padding()
        .frame(width: 260)
        .onChange(of: target) {
            if dragging { sendSpeed(after: .milliseconds(300)) }
        }
        .onChange(of: treadmill.status?.targetSpeed, initial: true) { _, speed in
            // Follow the treadmill (e.g. remote changes) unless the user is dragging.
            if !dragging, let speed, ZiproProtocol.speedRange.contains(speed) { target = speed }
        }
    }

    private func sendSpeed(after delay: Duration) {
        pendingSend?.cancel()
        pendingSend = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            treadmill.setSpeed(target)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        guard enabled != (service.status == .enabled) else { return }
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            NSLog("ZiproBar: launch at login failed: \(error)")
        }
        launchAtLogin = service.status == .enabled
    }

    private func quit() {
        Task {
            if state == .running || state == .countdown {
                treadmill.stop()
                await treadmill.flush()
            }
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusText: String {
        switch treadmill.connection {
        case .bluetoothUnavailable: return "Bluetooth unavailable"
        case .scanning: return "Searching for treadmill…"
        case .connecting: return "Connecting…"
        case .connected: break
        }
        switch state {
        case nil: return "Waiting for treadmill…"
        case .idle: return "Ready"
        case .countdown: return "Starting in \(treadmill.status?.elapsed ?? 0)…"
        case .running: return "Running"
        case .stopping: return "Stopping…"
        case .stopped: return "Stopped"
        case .sleeping: return "Sleeping – wake it with the remote"
        case .unknown(let byte): return String(format: "State 0x%02x", byte)
        }
    }

    private var statusColor: Color {
        guard connected else { return .gray }
        switch state {
        case .running: return .green
        case .countdown, .stopping: return .orange
        case .sleeping: return .gray
        default: return .blue
        }
    }
}

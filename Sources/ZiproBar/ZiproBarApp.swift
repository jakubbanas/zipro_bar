import SwiftUI
import ZiproKit

@main
struct ZiproBarApp: App {
    @State private var treadmill = Treadmill()

    var body: some Scene {
        MenuBarExtra {
            ControlView(treadmill: treadmill)
        } label: {
            MenuBarLabel(treadmill: treadmill)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let treadmill: Treadmill

    var body: some View {
        if treadmill.connection != .connected {
            Image(systemName: "figure.stand")
        } else if let status = treadmill.status, status.state == .running {
            Image(systemName: "figure.walk.motion")
            Text(status.speed, format: .number.precision(.fractionLength(1)))
        } else {
            Image(systemName: "figure.walk")
        }
    }
}

import SwiftUI

/// First-run permissions flow. Polls the three TCC preflights every second
/// and deep-links to the matching System Settings pane. Input Monitoring
/// grants sometimes only take effect after a relaunch — the row says so.
struct OnboardingView: View {
    @State private var mic = Permissions.microphoneGranted
    @State private var ax = Permissions.accessibilityGranted
    @State private var listen = Permissions.inputMonitoringGranted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var onAllGranted: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to MacTyper")
                .font(.title.bold())
            Text("Hold Right ⌘ (or long-press the left mouse button in a text field) and speak — your words are typed where the cursor is. MacTyper needs three permissions:")
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                granted: mic,
                icon: "mic.fill",
                title: "Microphone",
                detail: "Records your voice while you hold the trigger.",
                request: { Permissions.requestMicrophone { _ in } },
                pane: .microphone)

            permissionRow(
                granted: ax,
                icon: "accessibility",
                title: "Accessibility",
                detail: "Finds the text cursor and delivers the transcript with a synthetic ⌘V.",
                request: { Permissions.requestAccessibility() },
                pane: .accessibility)

            permissionRow(
                granted: listen,
                icon: "keyboard.fill",
                title: "Input Monitoring",
                detail: "Detects the Right ⌘ / F18 / mouse triggers. If dictation doesn't react after granting, quit and reopen MacTyper.",
                request: { Permissions.requestInputMonitoring() },
                pane: .inputMonitoring)

            if mic && ax && listen {
                Label("All set! Hold Right ⌘ and speak.", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
        }
        .padding(28)
        .frame(width: 560)
        .onReceive(timer) { _ in
            mic = Permissions.microphoneGranted
            ax = Permissions.accessibilityGranted
            listen = Permissions.inputMonitoringGranted
            if mic && ax && listen { onAllGranted() }
        }
    }

    @ViewBuilder
    private func permissionRow(granted: Bool, icon: String, title: String, detail: String,
                               request: @escaping () -> Void, pane: Permissions.Pane) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : icon)
                .font(.title2)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button("Grant…") {
                    request()
                    Permissions.openSystemSettings(pane: pane)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }
}

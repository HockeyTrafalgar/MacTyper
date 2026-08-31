import SwiftUI

/// Permissions section embedded in the Settings window. Polls the three
/// TCC preflights every second and deep-links to the matching System
/// Settings pane. Input Monitoring grants sometimes only take effect after
/// a relaunch — the row says so.
struct PermissionsSection: View {
    @State private var mic = Permissions.microphoneGranted
    @State private var ax = Permissions.accessibilityGranted
    @State private var listen = Permissions.inputMonitoringGranted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var onAllGranted: () -> Void = {}

    var body: some View {
        Section {
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
        } header: {
            Text("Permissions")
        } footer: {
            if mic && ax && listen {
                Label("All permissions granted — hold Right ⌘ and speak.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
        .onReceive(timer) { _ in
            let allBefore = mic && ax && listen
            mic = Permissions.microphoneGranted
            ax = Permissions.accessibilityGranted
            listen = Permissions.inputMonitoringGranted
            if !allBefore && mic && ax && listen { onAllGranted() }
        }
    }

    @ViewBuilder
    private func permissionRow(granted: Bool, icon: String, title: String, detail: String,
                               request: @escaping () -> Void, pane: Permissions.Pane) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : icon)
                .font(.title3)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.vertical, 2)
    }
}

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onRequestAccessibility: () -> Void
    let onRequestScreenRecording: () -> Void

    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Layout", selection: $settings.layout) {
                    ForEach(SwitcherLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                if settings.layout == .grid {
                    Stepper(
                        "Maximum columns: \(settings.gridColumns)",
                        value: $settings.gridColumns,
                        in: 2...6
                    )
                }

                Picker("Preview size", selection: $settings.previewSize) {
                    ForEach(PreviewSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }

                Toggle("Show window titles", isOn: $settings.showWindowTitles)
            }

            Section("General") {
                HStack {
                    Label("Launch at Login", systemImage: "power")
                    Spacer()
                    Button(settings.launchAtLogin ? "Disable" : "Enable") {
                        updateLaunchAtLogin(!settings.launchAtLogin)
                    }
                }
                LabeledContent("Shortcut", value: "⌥ Tab")
                LabeledContent("Shortcut status", value: settings.shortcutStatus.title)
                LabeledContent("Preview status", value: settings.previewStatus.title)
            }

            Section("Permissions") {
                permissionRow(
                    title: "Accessibility",
                    granted: PermissionManager.hasAccessibilityAccess,
                    action: onRequestAccessibility
                )
                permissionRow(
                    title: "Screen Recording",
                    granted: PermissionManager.hasScreenRecordingAccess,
                    action: onRequestScreenRecording
                )
                if settings.previewStatus == .permissionRequired {
                    Text("Enable AltTabber in Screen & System Audio Recording, then quit and reopen it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 500, height: 420)
        .alert(
            "Couldn’t Update Setting",
            isPresented: $isShowingError
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Label(
                title,
                systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle"
            )
            .foregroundStyle(granted ? .green : .primary)
            Spacer()
            if !granted {
                Button("Grant…", action: action)
            }
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try settings.setLaunchAtLogin(enabled)
        } catch {
            errorMessage = error.localizedDescription
            isShowingError = true
        }
    }
}

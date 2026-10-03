import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String, Hashable {
    case general, shortcuts, layouts, ignored, permissions
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

struct SettingsView: View {
    @ObservedObject var navigation: SettingsNavigation
    let library: LayoutLibrary
    let settings: AppSettings
    let updater: Updater

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralPane(updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ShortcutsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)
            LayoutsPane(library: library)
                .tabItem { Label("Layouts", systemImage: "rectangle.split.3x1") }
                .tag(SettingsTab.layouts)
            IgnoredAppsPane(settings: settings)
                .tabItem { Label("Ignored Apps", systemImage: "nosign") }
                .tag(SettingsTab.ignored)
            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
        }
        .frame(width: 720, height: 520)
    }
}

private struct GeneralPane: View {
    @ObservedObject var updater: Updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        Form {
            Toggle("Launch Split at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let loginError {
                Text(loginError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if updater.isAvailable {
                Toggle("Check for updates automatically",
                       isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
            }
            LabeledContent("Version") {
                HStack(spacing: 12) {
                    Text(version)
                    if updater.isAvailable {
                        Button("Check for Updates…") { updater.checkForUpdates() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
    }
}

private struct ShortcutsPane: View {
    var body: some View {
        Form {
            Section("Picker") {
                KeyboardShortcuts.Recorder("Open layout picker", name: .openPicker)
            }
            Section("Move focused window") {
                KeyboardShortcuts.Recorder("Left", name: .moveLeft)
                KeyboardShortcuts.Recorder("Right", name: .moveRight)
                KeyboardShortcuts.Recorder("Up", name: .moveUp)
                KeyboardShortcuts.Recorder("Down", name: .moveDown)
            }
        }
        .formStyle(.grouped)
    }
}

private struct IgnoredAppsPane: View {
    @ObservedObject var settings: AppSettings
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Split never snaps windows of these apps and leaves them out of Snap Assist.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(16)

            List(selection: $selection) {
                ForEach(settings.ignoredBundleIDs, id: \.self) { bundleID in
                    AppRow(bundleID: bundleID).tag(bundleID as String?)
                }
            }
            .overlay {
                if settings.ignoredBundleIDs.isEmpty {
                    Text("No ignored apps")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack(spacing: 4) {
                Button(action: addApp) {
                    Image(systemName: "plus").frame(width: 24, height: 24)
                }
                .accessibilityLabel("Add app")
                Button {
                    settings.ignoredBundleIDs.removeAll { $0 == selection }
                    selection = nil
                } label: {
                    Image(systemName: "minus").frame(width: 24, height: 24)
                }
                .disabled(selection == nil)
                .accessibilityLabel("Remove app")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  !settings.ignoredBundleIDs.contains(bundleID) else { continue }
            settings.ignoredBundleIDs.append(bundleID)
        }
    }
}

private struct AppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 20, height: 20)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
    }
}

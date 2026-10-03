import Combine
import SwiftUI

struct PermissionsView: View {
    @State private var accessibility = Permissions.accessibility
    @State private var screenRecording = Permissions.screenRecording

    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Split needs your permission")
                .font(.title2.bold())

            PermissionRow(title: "Accessibility",
                          detail: "Required. Lets Split move and resize windows.",
                          granted: accessibility,
                          request: Permissions.requestAccessibility)

            PermissionRow(title: "Screen Recording",
                          detail: "Optional. Shows window thumbnails in Snap Assist. Takes effect after Split restarts.",
                          granted: screenRecording,
                          request: Permissions.requestScreenRecording)
        }
        .padding(24)
        .frame(width: 460)
        .onReceive(refresh) { _ in
            accessibility = Permissions.accessibility
            screenRecording = Permissions.screenRecording
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(granted ? Color.green : Color.secondary)
                .accessibilityLabel(granted ? "Granted" : "Not granted")

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !granted {
                Button("Grant…", action: request)
            }
        }
    }
}

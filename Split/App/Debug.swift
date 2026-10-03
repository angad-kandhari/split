import CoreGraphics
import Foundation
import SplitCore

/// Development aids. Compiled out of release builds.
enum DebugLog {
    static func write(_ message: @autoclosure () -> String) {
        #if DEBUG
        let line = "\(Date().timeIntervalSince1970) \(message())\n"
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Split-debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: url)
        }
        #endif
    }
}

#if DEBUG
/// Lets test scripts drive the app without synthesising key presses:
/// post a distributed notification whose object is "status", "move:<direction>[:<pid>]",
/// "snap:<layout id>:<zone>[:<pid>]", "picker:open[:<pid>]", "picker:close", "picker:digit:<n>", "assist:select:<window id>" or "assist:dismiss". With a pid the command acts on that app's focused window, so tests
/// do not touch whatever the person at the keyboard is using.
@MainActor
enum DebugCommands {
    static let notification = Notification.Name("com.angadkandhari.Split.debug.command")

    static func listen(engine: SnapEngine, picker: PickerController, assist: SnapAssistController) {
        DistributedNotificationCenter.default().addObserver(forName: notification, object: nil, queue: .main) { note in
            guard let command = note.object as? String else { return }
            MainActor.assumeIsolated { run(command, engine: engine, picker: picker, assist: assist) }
        }
    }

    private static func run(_ command: String, engine: SnapEngine, picker: PickerController,
                            assist: SnapAssistController) {
        let parts = command.split(separator: ":").map(String.init)
        switch parts.first {
        case "status":
            DebugLog.write("status accessibility=\(Permissions.accessibility) screenRecording=\(Permissions.screenRecording)")
        case "move":
            guard parts.count >= 2, let direction = Direction(rawValue: parts[1]) else { return }
            engine.moveFocusedWindow(direction, inAppWithPID: parts.count > 2 ? pid_t(parts[2]) : nil)
        case "snap":
            guard parts.count >= 3, let zone = Int(parts[2]),
                  let layout = Layout.builtIns.first(where: { $0.id == parts[1] }) else { return }
            engine.snapFocusedWindow(to: layout, zone: zone, inAppWithPID: parts.count > 3 ? pid_t(parts[3]) : nil)
        case "picker":
            switch parts.dropFirst().first {
            case "open": picker.open(targetPID: parts.count > 2 ? pid_t(parts[2]) : nil)
            case "close": picker.close()
            case "digit": if parts.count > 2, let digit = Int(parts[2]) { _ = picker.model.handleDigit(digit) }
            default: break
            }
        case "assist":
            switch parts.dropFirst().first {
            case "select": if parts.count > 2, let id = CGWindowID(parts[2]) { assist.select(id) }
            case "dismiss": assist.dismiss()
            default: break
            }
        default:
            DebugLog.write("unknown command \(command)")
        }
    }
}
#endif

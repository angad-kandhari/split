import Foundation
#if !DEBUG
import Sparkle
#endif

/// Wraps Sparkle so the rest of the app does not depend on it.
/// Development builds never update themselves.
@MainActor
final class Updater: ObservableObject {
    #if DEBUG
    let isAvailable = false
    var automaticallyChecks: Bool {
        get { false }
        set {}
    }

    func checkForUpdates() {}
    #else
    let isAvailable = true
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                          userDriverDelegate: nil)

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
    #endif
}

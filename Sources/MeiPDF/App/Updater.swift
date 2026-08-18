import SwiftUI
import Sparkle

/// Hosts the Sparkle updater. Must be created after NSApplication is running,
/// so it is lazily initialized on first access (always from a menu action here).
@MainActor
final class UpdaterHost {
    static let shared = UpdaterHost()

    let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}

import Foundation
import ServiceManagement

/// A menu bar utility that does not come back after a quit, a crash, or a reboot is simply
/// gone: there is no Dock icon and no window to reopen it from, so the app silently ceases
/// to exist until someone relaunches it by hand. Registering with the login service is what
/// makes the status item durable.
enum LoginItem {
    private static let configuredKey = "openAtLoginConfigured"

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers once, on first launch, and records that it did. A later opt-out is then
    /// respected rather than being re-applied on every start.
    static func registerOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: configuredKey) else { return }
        UserDefaults.standard.set(true, forKey: configuredKey)
        setEnabled(true)
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, .enabled), (false, .notRegistered), (false, .notFound):
                return true
            case (true, _):
                try SMAppService.mainApp.register()
            case (false, _):
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            // Registration legitimately fails for a bundle macOS considers unstable, such as
            // one still sitting in a download or build directory. Not fatal: the app runs,
            // it just will not relaunch itself.
            return false
        }
    }
}

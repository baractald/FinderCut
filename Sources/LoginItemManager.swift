import Foundation
import ServiceManagement

final class LoginItemManager {
    enum ToggleResult: Equatable {
        case success
        case requiresApproval
        case failed(String)
    }

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> ToggleResult {
        guard #available(macOS 13.0, *) else {
            return .failed("macOS 13.0 or later is required.")
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    return .requiresApproval
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func openLoginItemsSettings() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}

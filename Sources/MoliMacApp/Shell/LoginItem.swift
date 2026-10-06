import ServiceManagement

enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    /// Covers both "active" and "waiting for approval in System Settings". Both have
    /// to be unregistered rather than registered again, so the toggle shows them as on.
    var isRegistered: Bool {
        self == .enabled || self == .requiresApproval
    }
}

/// Launch at login through `SMAppService.mainApp`: the app itself is the login item,
/// there is no separate helper.
@MainActor
enum LoginItem {
    static var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        case .notRegistered: .notRegistered
        @unknown default: .notRegistered
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

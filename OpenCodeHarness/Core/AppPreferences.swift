import Foundation
import Security
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum InspectorSection: String, CaseIterable, Identifiable {
    case files
    case changes
    case details

    var id: String { rawValue }
    var title: String {
        switch self {
        case .files: "Files"
        case .changes: "Changes"
        case .details: "Details"
        }
    }
    var icon: String {
        switch self {
        case .files: "folder"
        case .changes: "plus.forwardslash.minus"
        case .details: "sidebar.right"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var connectionMode: ServerMode {
        didSet { defaults.set(connectionMode.rawValue, forKey: Keys.connectionMode) }
    }
    @Published var binaryPath: String {
        didSet { defaults.set(binaryPath, forKey: Keys.binaryPath) }
    }
    @Published var remoteURL: String {
        didSet { defaults.set(remoteURL, forKey: Keys.remoteURL) }
    }
    @Published var remotePassword: String {
        didSet { KeychainStore.set(remotePassword, for: Keys.remotePassword) }
    }
    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var completionSound: Bool {
        didSet { defaults.set(completionSound, forKey: Keys.completionSound) }
    }
    @Published var showInspector: Bool {
        didSet { defaults.set(showInspector, forKey: Keys.showInspector) }
    }
    @Published var inspectorSection: InspectorSection {
        didSet { defaults.set(inspectorSection.rawValue, forKey: Keys.inspectorSection) }
    }
    @Published var showToolDetails: Bool {
        didSet { defaults.set(showToolDetails, forKey: Keys.showToolDetails) }
    }
    @Published var archivedVisible: Bool {
        didSet { defaults.set(archivedVisible, forKey: Keys.archivedVisible) }
    }
    @Published var lastModelKey: String {
        didSet { defaults.set(lastModelKey, forKey: Keys.lastModelKey) }
    }
    @Published var lastAgent: String {
        didSet { defaults.set(lastAgent, forKey: Keys.lastAgent) }
    }
    @Published var lastWorkspace: String {
        didSet { defaults.set(lastWorkspace, forKey: Keys.lastWorkspace) }
    }
    @Published var lastSessionID: String {
        didSet { defaults.set(lastSessionID, forKey: Keys.lastSessionID) }
    }
    @Published var recentWorkspaces: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(recentWorkspaces) {
                defaults.set(data, forKey: Keys.recentWorkspaces)
            }
        }
    }
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }
    @Published var includeArchivedInSearch: Bool {
        didSet { defaults.set(includeArchivedInSearch, forKey: Keys.includeArchivedInSearch) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        connectionMode = ServerMode(rawValue: defaults.string(forKey: Keys.connectionMode) ?? "") ?? .local
        binaryPath = defaults.string(forKey: Keys.binaryPath) ?? ""
        remoteURL = defaults.string(forKey: Keys.remoteURL) ?? "http://127.0.0.1:4096"
        remotePassword = KeychainStore.get(Keys.remotePassword) ?? ""
        theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        completionSound = defaults.object(forKey: Keys.completionSound) as? Bool ?? true
        showInspector = defaults.object(forKey: Keys.showInspector) as? Bool ?? true
        inspectorSection = InspectorSection(rawValue: defaults.string(forKey: Keys.inspectorSection) ?? "") ?? .files
        showToolDetails = defaults.object(forKey: Keys.showToolDetails) as? Bool ?? false
        archivedVisible = defaults.object(forKey: Keys.archivedVisible) as? Bool ?? false
        lastModelKey = defaults.string(forKey: Keys.lastModelKey) ?? ""
        lastAgent = defaults.string(forKey: Keys.lastAgent) ?? "build"
        lastWorkspace = defaults.string(forKey: Keys.lastWorkspace) ?? ""
        lastSessionID = defaults.string(forKey: Keys.lastSessionID) ?? ""
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
        includeArchivedInSearch = defaults.object(forKey: Keys.includeArchivedInSearch) as? Bool ?? false
        if let data = defaults.data(forKey: Keys.recentWorkspaces),
           let values = try? JSONDecoder().decode([String].self, from: data) {
            recentWorkspaces = values
        } else {
            recentWorkspaces = []
        }
    }

    func recordWorkspace(_ path: String) {
        guard !path.isEmpty else { return }
        lastWorkspace = path
        var values = recentWorkspaces.filter { $0 != path }
        values.insert(path, at: 0)
        recentWorkspaces = Array(values.prefix(12))
    }

    func forgetWorkspace(_ path: String) {
        recentWorkspaces.removeAll { $0 == path }
        if lastWorkspace == path { lastWorkspace = recentWorkspaces.first ?? "" }
    }

    private enum Keys {
        static let connectionMode = "connectionMode"
        static let binaryPath = "binaryPath"
        static let remoteURL = "remoteURL"
        static let remotePassword = "remotePassword"
        static let theme = "theme"
        static let completionSound = "completionSound"
        static let showInspector = "showInspector"
        static let inspectorSection = "inspectorSection"
        static let showToolDetails = "showToolDetails"
        static let archivedVisible = "archivedVisible"
        static let lastModelKey = "lastModelKey"
        static let lastAgent = "lastAgent"
        static let lastWorkspace = "lastWorkspace"
        static let lastSessionID = "lastSessionID"
        static let recentWorkspaces = "recentWorkspaces"
        static let notificationsEnabled = "notificationsEnabled"
        static let includeArchivedInSearch = "includeArchivedInSearch"
    }
}

enum KeychainStore {
    static func set(_ value: String, for key: String) {
        let service = "ai.opencode.harness"
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "ai.opencode.harness",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

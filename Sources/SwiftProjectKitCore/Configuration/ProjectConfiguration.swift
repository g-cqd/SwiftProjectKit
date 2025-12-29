import Foundation

// MARK: - PlatformConfiguration

/// Platform configuration for Swift projects
public struct PlatformConfiguration: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        iOS: String? = "18.0",
        macOS: String? = "15.0",
        watchOS: String? = "11.0",
        tvOS: String? = "18.0",
        visionOS: String? = "2.0",
    ) {
        self.iOS = iOS
        self.macOS = macOS
        self.watchOS = watchOS
        self.tvOS = tvOS
        self.visionOS = visionOS
    }

    // MARK: Public

    /// Default all-platform configuration
    public static let allPlatforms = PlatformConfiguration()

    /// macOS-only configuration
    public static let macOSOnly = PlatformConfiguration(
        iOS: nil,
        macOS: "15.0",
        watchOS: nil,
        tvOS: nil,
        visionOS: nil,
    )

    /// Apple platforms (iOS, macOS)
    public static let applePlatforms = PlatformConfiguration(
        iOS: "18.0",
        macOS: "15.0",
        watchOS: nil,
        tvOS: nil,
        visionOS: nil,
    )

    public var iOS: String?
    public var macOS: String?
    public var watchOS: String?
    public var tvOS: String?
    public var visionOS: String?

    /// Returns only the platforms that are set
    public var enabledPlatforms: [String] {
        var platforms: [String] = []
        if iOS != nil { platforms.append("iOS") }
        if macOS != nil { platforms.append("macOS") }
        if watchOS != nil { platforms.append("watchOS") }
        if tvOS != nil { platforms.append("tvOS") }
        if visionOS != nil { platforms.append("visionOS") }
        return platforms
    }
}

// MARK: - ToolConfiguration

/// Tool configuration for linting and formatting
public struct ToolConfiguration: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(enabled: Bool = true, version: String? = nil, configPath: String? = nil) {
        self.enabled = enabled
        self.version = version
        self.configPath = configPath
    }

    // MARK: Public

    public var enabled: Bool
    public var version: String?
    public var configPath: String?
}

// MARK: - WorkflowConfiguration

/// Workflow configuration
public struct WorkflowConfiguration: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(ci: Bool = true, release: Bool = true, docs: Bool = true) {
        self.ci = ci
        self.release = release
        self.docs = docs
    }

    // MARK: Public

    public var ci: Bool
    public var release: Bool
    public var docs: Bool
}

// MARK: - ProjectConfiguration

/// Main project configuration model
/// Loaded from `.swiftprojectkit.json` in project root
public struct ProjectConfiguration: Codable, Sendable, Equatable {
    // MARK: Lifecycle

    public init(
        version: String = "1.0",
        swiftVersion: String = "6.2",
        platforms: PlatformConfiguration = .allPlatforms,
        swiftlint: ToolConfiguration = .init(),
        swiftformat: ToolConfiguration = .init(),
        workflows: WorkflowConfiguration = .init(),
    ) {
        self.version = version
        self.swiftVersion = swiftVersion
        self.platforms = platforms
        self.swiftlint = swiftlint
        self.swiftformat = swiftformat
        self.workflows = workflows
    }

    // MARK: Public

    /// Default configuration
    public static let `default` = ProjectConfiguration()

    public var version: String
    public var swiftVersion: String
    public var platforms: PlatformConfiguration
    public var swiftlint: ToolConfiguration
    public var swiftformat: ToolConfiguration
    public var workflows: WorkflowConfiguration

    /// Load configuration from a directory
    public static func load(from directory: URL) throws -> ProjectConfiguration {
        let configPath = directory.appendingPathComponent(".swiftprojectkit.json")

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return .default
        }

        let data = try Data(contentsOf: configPath)
        return try JSONDecoder().decode(ProjectConfiguration.self, from: data)
    }

    /// Save configuration to a directory
    public func save(to directory: URL) throws {
        let configPath = directory.appendingPathComponent(".swiftprojectkit.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: configPath)
    }
}

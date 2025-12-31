import Foundation
import RegexBuilder

// MARK: - SemanticVersion

/// Semantic versioning type for project version management.
///
/// Supports major.minor.patch format with optional pre-release and build metadata.
public struct SemanticVersion: Codable, Sendable, Equatable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    public var preRelease: String?
    public var buildMetadata: String?

    public init(
        major: Int,
        minor: Int,
        patch: Int,
        preRelease: String? = nil,
        buildMetadata: String? = nil
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.preRelease = preRelease
        self.buildMetadata = buildMetadata
    }

    /// Parse from string like "1.2.3", "1.2.3-beta.1", or "1.2.3-beta.1+build.123"
    public init?(string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Pattern: major.minor.patch[-prerelease][+build]
        // Using RegexBuilder for type-safe pattern matching
        let digits = OneOrMore(.digit)
        let preReleaseChars = CharacterClass(.word, .anyOf(".-"))
        let buildMetadataChars = CharacterClass(.word, .anyOf(".-"))

        let pattern = Regex {
            Anchor.startOfSubject
            Capture { digits }
            "."
            Capture { digits }
            "."
            Capture { digits }
            Optionally {
                "-"
                Capture { OneOrMore(preReleaseChars) }
            }
            Optionally {
                "+"
                Capture { OneOrMore(buildMetadataChars) }
            }
            Anchor.endOfSubject
        }

        guard let match = trimmed.firstMatch(of: pattern) else {
            return nil
        }

        guard let major = Int(match.1),
            let minor = Int(match.2),
            let patch = Int(match.3)
        else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        preRelease = match.4.map(String.init)
        buildMetadata = match.5.map(String.init)
    }

    public var description: String {
        var result = "\(major).\(minor).\(patch)"
        if let preRelease {
            result += "-\(preRelease)"
        }
        if let buildMetadata {
            result += "+\(buildMetadata)"
        }
        return result
    }

    /// Version string without pre-release or build metadata
    public var coreVersion: String {
        "\(major).\(minor).\(patch)"
    }

    /// Bump major version (resets minor and patch to 0)
    public func bumpMajor() -> SemanticVersion {
        SemanticVersion(major: major + 1, minor: 0, patch: 0)
    }

    /// Bump minor version (resets patch to 0)
    public func bumpMinor() -> SemanticVersion {
        SemanticVersion(major: major, minor: minor + 1, patch: 0)
    }

    /// Bump patch version
    public func bumpPatch() -> SemanticVersion {
        SemanticVersion(major: major, minor: minor, patch: patch + 1)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Pre-release versions have lower precedence than release
        switch (lhs.preRelease, rhs.preRelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case (let lhsPre?, let rhsPre?): return lhsPre < rhsPre
        }
    }

    // Custom Codable to support both string and object formats
    public init(from decoder: Decoder) throws {
        // Try string format first
        if let container = try? decoder.singleValueContainer(),
            let string = try? container.decode(String.self),
            let version = SemanticVersion(string: string)
        {
            self = version
            return
        }

        // Fall back to object format
        let container = try decoder.container(keyedBy: CodingKeys.self)
        major = try container.decode(Int.self, forKey: .major)
        minor = try container.decode(Int.self, forKey: .minor)
        patch = try container.decode(Int.self, forKey: .patch)
        preRelease = try container.decodeIfPresent(String.self, forKey: .preRelease)
        buildMetadata = try container.decodeIfPresent(String.self, forKey: .buildMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        // Encode as string for simplicity
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private enum CodingKeys: String, CodingKey {
        case major, minor, patch, preRelease, buildMetadata
    }
}

// MARK: - VersionConfiguration

/// Configuration for project version management.
public struct VersionConfiguration: Codable, Sendable, Equatable {
    /// The current version
    public var current: SemanticVersion

    /// File that contains the source of truth version (e.g., "VERSION")
    public var sourceFile: String?

    /// Files to sync version to
    public var syncTargets: [VersionSyncTarget]

    public init(
        current: SemanticVersion = SemanticVersion(major: 0, minor: 0, patch: 1),
        sourceFile: String? = "VERSION",
        syncTargets: [VersionSyncTarget] = []
    ) {
        self.current = current
        self.sourceFile = sourceFile
        self.syncTargets = syncTargets
    }

    public struct VersionSyncTarget: Codable, Sendable, Equatable {
        public var file: String
        public var pattern: String

        public init(file: String, pattern: String) {
            self.file = file
            self.pattern = pattern
        }
    }
}

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
    public static let allPlatforms = Self()

    /// macOS-only configuration
    public static let macOSOnly = Self(
        iOS: nil,
        macOS: "15.0",
        watchOS: nil,
        tvOS: nil,
        visionOS: nil,
    )

    /// Apple platforms (iOS, macOS)
    public static let applePlatforms = Self(
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
        swiftformat: ToolConfiguration = .init(),
        workflows: WorkflowConfiguration = .init(),
    ) {
        self.version = version
        self.swiftVersion = swiftVersion
        self.platforms = platforms
        self.swiftformat = swiftformat
        self.workflows = workflows
    }

    // MARK: Public

    /// Default configuration
    public static let `default` = Self()

    public var version: String
    public var swiftVersion: String
    public var platforms: PlatformConfiguration
    /// swift-format configuration
    public var swiftformat: ToolConfiguration
    public var workflows: WorkflowConfiguration

    /// Load configuration from a directory
    public static func load(from directory: URL) throws -> Self {
        let configPath = directory.appendingPathComponent(".swiftprojectkit.json")

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return .default
        }

        let data = try Data(contentsOf: configPath)
        return try JSONDecoder().decode(Self.self, from: data)
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

import Foundation
@testable import SwiftProjectKitCore
import Testing

// MARK: - PlatformConfigurationTests

@Suite("PlatformConfiguration Tests")
struct PlatformConfigurationTests {
    @Test("Default initialization includes all platforms")
    func defaultInitialization() {
        let config = PlatformConfiguration()

        #expect(config.iOS == "18.0")
        #expect(config.macOS == "15.0")
        #expect(config.watchOS == "11.0")
        #expect(config.tvOS == "18.0")
        #expect(config.visionOS == "2.0")
    }

    @Test("enabledPlatforms returns only non-nil platforms")
    func testEnabledPlatforms() {
        let allPlatforms = PlatformConfiguration()
        #expect(allPlatforms.enabledPlatforms.count == 5)
        #expect(allPlatforms.enabledPlatforms.contains("iOS"))
        #expect(allPlatforms.enabledPlatforms.contains("macOS"))
        #expect(allPlatforms.enabledPlatforms.contains("watchOS"))
        #expect(allPlatforms.enabledPlatforms.contains("tvOS"))
        #expect(allPlatforms.enabledPlatforms.contains("visionOS"))

        let macOSOnly = PlatformConfiguration.macOSOnly
        #expect(macOSOnly.enabledPlatforms.count == 1)
        #expect(macOSOnly.enabledPlatforms.contains("macOS"))
    }

    @Test("macOSOnly preset has correct values")
    func macOSOnlyPreset() {
        let config = PlatformConfiguration.macOSOnly

        #expect(config.iOS == nil)
        #expect(config.macOS == "15.0")
        #expect(config.watchOS == nil)
        #expect(config.tvOS == nil)
        #expect(config.visionOS == nil)
    }

    @Test("applePlatforms preset has correct values")
    func applePlatformsPreset() {
        let config = PlatformConfiguration.applePlatforms

        #expect(config.iOS == "18.0")
        #expect(config.macOS == "15.0")
        #expect(config.watchOS == nil)
        #expect(config.tvOS == nil)
        #expect(config.visionOS == nil)
    }

    @Test("allPlatforms static property matches default init")
    func allPlatformsStatic() {
        let allPlatforms = PlatformConfiguration.allPlatforms
        let defaultInit = PlatformConfiguration()

        #expect(allPlatforms == defaultInit)
    }

    @Test("Custom initialization works correctly")
    func customInitialization() {
        let config = PlatformConfiguration(
            iOS: "17.0",
            macOS: nil,
            watchOS: "10.0",
            tvOS: nil,
            visionOS: nil,
        )

        #expect(config.iOS == "17.0")
        #expect(config.macOS == nil)
        #expect(config.watchOS == "10.0")
        #expect(config.tvOS == nil)
        #expect(config.visionOS == nil)
        #expect(config.enabledPlatforms.count == 2)
    }

    @Test("PlatformConfiguration is Codable")
    func codable() throws {
        let original = PlatformConfiguration(
            iOS: "17.0",
            macOS: "14.0",
            watchOS: nil,
            tvOS: nil,
            visionOS: nil,
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(PlatformConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("PlatformConfiguration is Equatable")
    func equatable() {
        let config1 = PlatformConfiguration.macOSOnly
        let config2 = PlatformConfiguration.macOSOnly
        let config3 = PlatformConfiguration.allPlatforms

        #expect(config1 == config2)
        #expect(config1 != config3)
    }
}

// MARK: - ToolConfigurationTests

@Suite("ToolConfiguration Tests")
struct ToolConfigurationTests {
    @Test("Default initialization has correct values")
    func testDefaultInitialization() {
        let config = ToolConfiguration()

        #expect(config.enabled == true)
        #expect(config.version == nil)
        #expect(config.configPath == nil)
    }

    @Test("Custom initialization works correctly")
    func testCustomInitialization() {
        let config = ToolConfiguration(
            enabled: false,
            version: "0.57.1",
            configPath: ".custom-swiftlint.yml",
        )

        #expect(config.enabled == false)
        #expect(config.version == "0.57.1")
        #expect(config.configPath == ".custom-swiftlint.yml")
    }

    @Test("ToolConfiguration is Codable")
    func testCodable() throws {
        let original = ToolConfiguration(
            enabled: true,
            version: "1.2.3",
            configPath: "/path/to/config",
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ToolConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("ToolConfiguration is Equatable")
    func testEquatable() {
        let config1 = ToolConfiguration(enabled: true, version: "1.0.0")
        let config2 = ToolConfiguration(enabled: true, version: "1.0.0")
        let config3 = ToolConfiguration(enabled: false, version: "1.0.0")

        #expect(config1 == config2)
        #expect(config1 != config3)
    }
}

// MARK: - WorkflowConfigurationTests

@Suite("WorkflowConfiguration Tests")
struct WorkflowConfigurationTests {
    @Test("Default initialization has all workflows enabled")
    func testDefaultInitialization() {
        let config = WorkflowConfiguration()

        #expect(config.ci == true)
        #expect(config.release == true)
        #expect(config.docs == true)
    }

    @Test("Custom initialization works correctly")
    func testCustomInitialization() {
        let config = WorkflowConfiguration(ci: true, release: false, docs: true)

        #expect(config.ci == true)
        #expect(config.release == false)
        #expect(config.docs == true)
    }

    @Test("WorkflowConfiguration is Codable")
    func testCodable() throws {
        let original = WorkflowConfiguration(ci: true, release: false, docs: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkflowConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("WorkflowConfiguration is Equatable")
    func testEquatable() {
        let config1 = WorkflowConfiguration(ci: true, release: true, docs: false)
        let config2 = WorkflowConfiguration(ci: true, release: true, docs: false)
        let config3 = WorkflowConfiguration(ci: false, release: true, docs: false)

        #expect(config1 == config2)
        #expect(config1 != config3)
    }
}

// MARK: - ProjectConfigurationTests

@Suite("ProjectConfiguration Tests")
struct ProjectConfigurationTests {
    @Test("Default initialization has correct values")
    func testDefaultInitialization() {
        let config = ProjectConfiguration()

        #expect(config.version == "1.0")
        #expect(config.swiftVersion == "6.2")
        #expect(config.platforms == .allPlatforms)
        #expect(config.swiftlint.enabled == true)
        #expect(config.swiftformat.enabled == true)
        #expect(config.workflows.ci == true)
    }

    @Test("Static default matches default initialization")
    func testStaticDefault() {
        let staticDefault = ProjectConfiguration.default
        let defaultInit = ProjectConfiguration()

        #expect(staticDefault == defaultInit)
    }

    @Test("Custom initialization works correctly")
    func testCustomInitialization() {
        let config = ProjectConfiguration(
            version: "2.0",
            swiftVersion: "5.9",
            platforms: .macOSOnly,
            swiftlint: ToolConfiguration(enabled: false),
            swiftformat: ToolConfiguration(enabled: true, version: "0.54.0"),
            workflows: WorkflowConfiguration(ci: true, release: false, docs: false),
        )

        #expect(config.version == "2.0")
        #expect(config.swiftVersion == "5.9")
        #expect(config.platforms == .macOSOnly)
        #expect(config.swiftlint.enabled == false)
        #expect(config.swiftformat.enabled == true)
        #expect(config.swiftformat.version == "0.54.0")
        #expect(config.workflows.release == false)
    }

    @Test("ProjectConfiguration is Codable")
    func testCodable() throws {
        let original = ProjectConfiguration(
            version: "1.5",
            swiftVersion: "6.0",
            platforms: PlatformConfiguration(iOS: "17.0", macOS: "14.0", watchOS: nil, tvOS: nil, visionOS: nil),
            swiftlint: ToolConfiguration(enabled: true, version: "0.57.0"),
            swiftformat: ToolConfiguration(enabled: false),
            workflows: WorkflowConfiguration(ci: true, release: true, docs: false),
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ProjectConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("ProjectConfiguration is Equatable")
    func testEquatable() {
        let config1 = ProjectConfiguration.default
        let config2 = ProjectConfiguration.default
        let config3 = ProjectConfiguration(version: "2.0")

        #expect(config1 == config2)
        #expect(config1 != config3)
    }

    @Test("save and load round-trip correctly")
    func saveAndLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let original = ProjectConfiguration(
            version: "1.5",
            swiftVersion: "6.1",
            platforms: .applePlatforms,
            swiftlint: ToolConfiguration(enabled: true, version: "0.57.1"),
            swiftformat: ToolConfiguration(enabled: true, version: "0.54.6"),
            workflows: WorkflowConfiguration(ci: true, release: true, docs: false),
        )

        try original.save(to: tempDir)

        let loaded = try ProjectConfiguration.load(from: tempDir)

        #expect(loaded == original)
    }

    @Test("load returns default when file doesn't exist")
    func loadReturnsDefault() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let loaded = try ProjectConfiguration.load(from: tempDir)

        #expect(loaded == .default)
    }

    @Test("JSON output is human-readable")
    func jSONFormat() throws {
        let config = ProjectConfiguration.default

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let jsonString = String(data: data, encoding: .utf8)

        #expect(jsonString != nil)
        #expect(jsonString?.contains("\"version\"") == true)
        #expect(jsonString?.contains("\"swiftVersion\"") == true)
        #expect(jsonString?.contains("\"platforms\"") == true)
    }
}

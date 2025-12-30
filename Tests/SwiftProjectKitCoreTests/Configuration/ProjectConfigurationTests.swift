// ProjectConfigurationTests.swift
// Tests for ProjectConfiguration model correctness.
//
// ## Test Goals
// - Verify default initialization provides sensible defaults
// - Ensure static .default matches default initialization
// - Test Codable conformance with all nested types
// - Test file I/O (save/load) operations
// - Validate JSON output format is human-readable
//
// ## Why These Tests Matter
// ProjectConfiguration is the root configuration model that drives
// all project scaffolding and management. Invalid serialization or
// defaults cause project setup failures.

import Foundation
@testable import SwiftProjectKitCore
import Testing

@Suite("ProjectConfiguration Tests")
struct ProjectConfigurationTests {
    // MARK: - Default Initialization

    @Test("Default initialization has version 1.0")
    func defaultVersion() {
        let config = ProjectConfiguration()

        #expect(config.version == "1.0", "Default version should be 1.0")
    }

    @Test("Default initialization has Swift 6.2")
    func defaultSwiftVersion() {
        let config = ProjectConfiguration()

        #expect(config.swiftVersion == "6.2", "Default Swift version should be 6.2")
    }

    @Test("Default initialization has all platforms")
    func defaultPlatforms() {
        let config = ProjectConfiguration()

        #expect(
            config.platforms == .allPlatforms,
            "Default should include all platforms",
        )
    }

    @Test("Default initialization enables SwiftLint")
    func defaultEnablesSwiftLint() {
        let config = ProjectConfiguration()

        #expect(config.swiftlint.enabled == true, "SwiftLint should be enabled")
    }

    @Test("Default initialization enables SwiftFormat")
    func defaultEnablesSwiftFormat() {
        let config = ProjectConfiguration()

        #expect(config.swiftformat.enabled == true, "SwiftFormat should be enabled")
    }

    @Test("Default initialization enables CI workflow")
    func defaultEnablesCI() {
        let config = ProjectConfiguration()

        #expect(config.workflows.ci == true, "CI workflow should be enabled")
    }

    // MARK: - Static Default

    @Test("Static .default matches default initialization")
    func staticDefaultMatchesInit() {
        let staticDefault = ProjectConfiguration.default
        let defaultInit = ProjectConfiguration()

        #expect(staticDefault == defaultInit)
    }

    // MARK: - Custom Initialization

    @Test("Custom initialization sets all values")
    func customInitialization() {
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

    // MARK: - Codable Conformance

    @Test("Encodes and decodes correctly")
    func codableRoundTrip() throws {
        let original = ProjectConfiguration(
            version: "1.5",
            swiftVersion: "6.0",
            platforms: PlatformConfiguration(
                iOS: "17.0",
                macOS: "14.0",
                watchOS: nil,
                tvOS: nil,
                visionOS: nil,
            ),
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

    @Test("Default config round-trips correctly")
    func defaultConfigRoundTrip() throws {
        let original = ProjectConfiguration.default

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ProjectConfiguration.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - Equatable Conformance

    @Test("Equal configurations are equal")
    func equalConfigsAreEqual() {
        let config1 = ProjectConfiguration.default
        let config2 = ProjectConfiguration.default

        #expect(config1 == config2)
    }

    @Test("Different versions are not equal")
    func differentVersionsNotEqual() {
        let config1 = ProjectConfiguration.default
        let config2 = ProjectConfiguration(version: "2.0")

        #expect(config1 != config2)
    }

    @Test("Different Swift versions are not equal")
    func differentSwiftVersionsNotEqual() {
        let config1 = ProjectConfiguration()
        let config2 = ProjectConfiguration(swiftVersion: "5.9")

        #expect(config1 != config2)
    }

    // MARK: - File I/O

    @Test("Save and load round-trip correctly")
    func saveAndLoadRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true,
        )

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

    @Test("Load returns default when file doesn't exist")
    func loadReturnsDefaultWhenFileMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true,
        )

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let loaded = try ProjectConfiguration.load(from: tempDir)

        #expect(loaded == .default, "Should return default when file doesn't exist")
    }

    @Test("Save creates .swiftprojectkit.json file")
    func saveCreatesCorrectFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true,
        )

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let config = ProjectConfiguration.default
        try config.save(to: tempDir)

        let expectedPath = tempDir.appendingPathComponent(".swiftprojectkit.json")
        #expect(
            FileManager.default.fileExists(atPath: expectedPath.path),
            "Should create .swiftprojectkit.json",
        )
    }

    // MARK: - JSON Format

    @Test("JSON output is human-readable")
    func jsonIsHumanReadable() throws {
        let config = ProjectConfiguration.default

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let jsonString = String(data: data, encoding: .utf8)

        #expect(jsonString != nil, "Should produce valid UTF-8 JSON")
        #expect(jsonString?.contains("\"version\"") == true)
        #expect(jsonString?.contains("\"swiftVersion\"") == true)
        #expect(jsonString?.contains("\"platforms\"") == true)
        #expect(jsonString?.contains("\"swiftlint\"") == true)
        #expect(jsonString?.contains("\"swiftformat\"") == true)
        #expect(jsonString?.contains("\"workflows\"") == true)
    }

    @Test("JSON output contains newlines for readability")
    func jsonContainsNewlines() throws {
        let config = ProjectConfiguration.default

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(config)
        let jsonString = String(data: data, encoding: .utf8) ?? ""

        let newlineCount = jsonString.count(where: { $0 == "\n" })
        #expect(newlineCount > 10, "Pretty-printed JSON should have multiple newlines")
    }
}

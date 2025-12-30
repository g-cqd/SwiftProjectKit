// PlatformConfigurationTests.swift
// Tests for PlatformConfiguration model correctness.
//
// ## Test Goals
// - Verify default initialization provides sensible platform versions
// - Ensure presets (macOSOnly, applePlatforms, allPlatforms) are correct
// - Validate enabledPlatforms computed property
// - Test Codable conformance for serialization
// - Test Equatable conformance for comparisons
//
// ## Why These Tests Matter
// PlatformConfiguration drives CI workflow generation and project scaffolding.
// Incorrect configurations lead to failed builds or wrong deployment targets.

import Foundation
import Testing

@testable import SwiftProjectKitCore

@Suite("PlatformConfiguration Tests")
struct PlatformConfigurationTests {
    // MARK: - Default Initialization

    @Test("Default initialization includes all platforms with current versions")
    func defaultInitialization() {
        let config = PlatformConfiguration()

        #expect(config.iOS != nil, "iOS should be enabled by default")
        #expect(config.macOS != nil, "macOS should be enabled by default")
        #expect(config.watchOS != nil, "watchOS should be enabled by default")
        #expect(config.tvOS != nil, "tvOS should be enabled by default")
        #expect(config.visionOS != nil, "visionOS should be enabled by default")
    }

    @Test("Default iOS version is current")
    func defaultIOSVersion() {
        let config = PlatformConfiguration()
        #expect(config.iOS == "18.0", "iOS should default to 18.0")
    }

    @Test("Default macOS version is current")
    func defaultMacOSVersion() {
        let config = PlatformConfiguration()
        #expect(config.macOS == "15.0", "macOS should default to 15.0")
    }

    @Test("Default watchOS version is current")
    func defaultWatchOSVersion() {
        let config = PlatformConfiguration()
        #expect(config.watchOS == "11.0", "watchOS should default to 11.0")
    }

    @Test("Default tvOS version is current")
    func defaultTVOSVersion() {
        let config = PlatformConfiguration()
        #expect(config.tvOS == "18.0", "tvOS should default to 18.0")
    }

    @Test("Default visionOS version is current")
    func defaultVisionOSVersion() {
        let config = PlatformConfiguration()
        #expect(config.visionOS == "2.0", "visionOS should default to 2.0")
    }

    // MARK: - Presets

    @Test("macOSOnly preset has only macOS enabled")
    func macOSOnlyPreset() {
        let config = PlatformConfiguration.macOSOnly

        #expect(config.iOS == nil, "iOS should be nil for macOSOnly")
        #expect(config.macOS == "15.0", "macOS should be 15.0")
        #expect(config.watchOS == nil, "watchOS should be nil for macOSOnly")
        #expect(config.tvOS == nil, "tvOS should be nil for macOSOnly")
        #expect(config.visionOS == nil, "visionOS should be nil for macOSOnly")
    }

    @Test("applePlatforms preset has iOS and macOS only")
    func applePlatformsPreset() {
        let config = PlatformConfiguration.applePlatforms

        #expect(config.iOS == "18.0", "iOS should be 18.0")
        #expect(config.macOS == "15.0", "macOS should be 15.0")
        #expect(config.watchOS == nil, "watchOS should be nil")
        #expect(config.tvOS == nil, "tvOS should be nil")
        #expect(config.visionOS == nil, "visionOS should be nil")
    }

    @Test("allPlatforms preset matches default initialization")
    func allPlatformsPreset() {
        let allPlatforms = PlatformConfiguration.allPlatforms
        let defaultInit = PlatformConfiguration()

        #expect(allPlatforms == defaultInit, "allPlatforms should match default init")
    }

    // MARK: - Enabled Platforms

    @Test("enabledPlatforms returns only non-nil platforms")
    func enabledPlatformsFiltersNil() {
        let config = PlatformConfiguration.macOSOnly
        let enabled = config.enabledPlatforms

        #expect(enabled.count == 1, "macOSOnly should have 1 enabled platform")
        #expect(enabled.contains("macOS"), "macOS should be in enabled list")
        #expect(!enabled.contains("iOS"), "iOS should not be in enabled list")
    }

    @Test("enabledPlatforms returns all 5 for default config")
    func enabledPlatformsReturnsAll() {
        let config = PlatformConfiguration()
        let enabled = config.enabledPlatforms

        #expect(enabled.count == 5, "Default should have 5 enabled platforms")
        #expect(enabled.contains("iOS"))
        #expect(enabled.contains("macOS"))
        #expect(enabled.contains("watchOS"))
        #expect(enabled.contains("tvOS"))
        #expect(enabled.contains("visionOS"))
    }

    @Test("enabledPlatforms for applePlatforms returns 2")
    func enabledPlatformsForApplePlatforms() {
        let config = PlatformConfiguration.applePlatforms
        let enabled = config.enabledPlatforms

        #expect(enabled.count == 2, "applePlatforms should have 2 enabled")
        #expect(enabled.contains("iOS"))
        #expect(enabled.contains("macOS"))
    }

    // MARK: - Custom Initialization

    @Test("Custom initialization sets values correctly")
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

    // MARK: - Codable Conformance

    @Test("Encodes and decodes correctly")
    func codableRoundTrip() throws {
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

        #expect(decoded == original, "Decoded should match original")
    }

    @Test("Encoded JSON has expected structure")
    func encodedJSONStructure() throws {
        let config = PlatformConfiguration.macOSOnly

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil, "Should produce valid JSON")
        #expect(json?["macOS"] as? String == "15.0")
    }

    // MARK: - Equatable Conformance

    @Test("Equal configurations are equal")
    func equalConfigsAreEqual() {
        let config1 = PlatformConfiguration.macOSOnly
        let config2 = PlatformConfiguration.macOSOnly

        #expect(config1 == config2)
    }

    @Test("Different configurations are not equal")
    func differentConfigsAreNotEqual() {
        let config1 = PlatformConfiguration.macOSOnly
        let config2 = PlatformConfiguration.allPlatforms

        #expect(config1 != config2)
    }

    @Test("Configs with different versions are not equal")
    func differentVersionsNotEqual() {
        let config1 = PlatformConfiguration(iOS: "17.0", macOS: nil, watchOS: nil, tvOS: nil, visionOS: nil)
        let config2 = PlatformConfiguration(iOS: "18.0", macOS: nil, watchOS: nil, tvOS: nil, visionOS: nil)

        #expect(config1 != config2)
    }
}

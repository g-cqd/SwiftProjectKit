// ToolConfigurationTests.swift
// Tests for ToolConfiguration model correctness.
//
// ## Test Goals
// - Verify default initialization enables tools
// - Ensure optional version and configPath work correctly
// - Test Codable conformance for serialization
// - Test Equatable conformance for comparisons
//
// ## Why These Tests Matter
// ToolConfiguration controls which linting/formatting tools are enabled
// and their versions. Incorrect defaults cause unexpected behavior.

import Foundation
import Testing

@testable import SwiftProjectKitCore

@Suite("ToolConfiguration Tests")
struct ToolConfigurationTests {
    // MARK: - Default Initialization

    @Test("Default initialization enables tool")
    func defaultEnablesToolByDefault() {
        let config = ToolConfiguration()

        #expect(config.enabled == true, "Tools should be enabled by default")
    }

    @Test("Default initialization has nil version")
    func defaultHasNilVersion() {
        let config = ToolConfiguration()

        #expect(config.version == nil, "Version should be nil by default (use tool default)")
    }

    @Test("Default initialization has nil configPath")
    func defaultHasNilConfigPath() {
        let config = ToolConfiguration()

        #expect(config.configPath == nil, "configPath should be nil by default")
    }

    // MARK: - Custom Initialization

    @Test("Custom initialization sets enabled correctly")
    func customInitializationEnabled() {
        let disabled = ToolConfiguration(enabled: false)
        let enabled = ToolConfiguration(enabled: true)

        #expect(disabled.enabled == false)
        #expect(enabled.enabled == true)
    }

    @Test("Custom initialization sets version correctly")
    func customInitializationVersion() {
        let config = ToolConfiguration(enabled: true, version: "0.57.1")

        #expect(config.version == "0.57.1")
    }

    @Test("Custom initialization sets configPath correctly")
    func customInitializationConfigPath() {
        let config = ToolConfiguration(
            enabled: true,
            version: nil,
            configPath: ".custom-swift-format",
        )

        #expect(config.configPath == ".custom-swift-format")
    }

    @Test("All parameters can be set together")
    func allParametersTogether() {
        let config = ToolConfiguration(
            enabled: false,
            version: "0.57.1",
            configPath: "/path/to/config",
        )

        #expect(config.enabled == false)
        #expect(config.version == "0.57.1")
        #expect(config.configPath == "/path/to/config")
    }

    // MARK: - Codable Conformance

    @Test("Encodes and decodes correctly with all fields")
    func codableRoundTripAllFields() throws {
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

    @Test("Encodes and decodes correctly with nil fields")
    func codableRoundTripNilFields() throws {
        let original = ToolConfiguration(enabled: true, version: nil, configPath: nil)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ToolConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("Encoded JSON has expected keys")
    func encodedJSONHasExpectedKeys() throws {
        let config = ToolConfiguration(enabled: true, version: "1.0.0", configPath: nil)

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["enabled"] as? Bool == true)
        #expect(json?["version"] as? String == "1.0.0")
    }

    // MARK: - Equatable Conformance

    @Test("Equal configurations are equal")
    func equalConfigsAreEqual() {
        let config1 = ToolConfiguration(enabled: true, version: "1.0.0")
        let config2 = ToolConfiguration(enabled: true, version: "1.0.0")

        #expect(config1 == config2)
    }

    @Test("Different enabled values are not equal")
    func differentEnabledNotEqual() {
        let config1 = ToolConfiguration(enabled: true)
        let config2 = ToolConfiguration(enabled: false)

        #expect(config1 != config2)
    }

    @Test("Different versions are not equal")
    func differentVersionsNotEqual() {
        let config1 = ToolConfiguration(enabled: true, version: "1.0.0")
        let config2 = ToolConfiguration(enabled: true, version: "2.0.0")

        #expect(config1 != config2)
    }

    @Test("Different configPaths are not equal")
    func differentConfigPathsNotEqual() {
        let config1 = ToolConfiguration(enabled: true, configPath: "/path/a")
        let config2 = ToolConfiguration(enabled: true, configPath: "/path/b")

        #expect(config1 != config2)
    }

    @Test("Nil and non-nil version are not equal")
    func nilAndNonNilVersionNotEqual() {
        let config1 = ToolConfiguration(enabled: true, version: nil)
        let config2 = ToolConfiguration(enabled: true, version: "1.0.0")

        #expect(config1 != config2)
    }
}

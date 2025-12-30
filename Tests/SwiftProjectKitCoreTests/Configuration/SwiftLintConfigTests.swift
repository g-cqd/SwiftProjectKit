// SwiftLintConfigTests.swift
// Tests for SwiftLint configuration template validity and structure.
//
// ## Test Goals
// - Verify the SwiftLint configuration is valid YAML that can be parsed
// - Ensure required sections exist with correct types
// - Validate rule configurations are sensible for modern Swift
// - Confirm excluded paths are properly configured
//
// ## Why These Tests Matter
// Invalid SwiftLint configuration will cause builds to fail or lint incorrectly.
// These tests catch configuration errors before they reach users.

import Foundation
@testable import SwiftProjectKitCore
import Testing
import Yams

// MARK: - SwiftLintConfigTests

@Suite("SwiftLint Configuration Tests")
struct SwiftLintConfigTests {
    // MARK: Internal

    // MARK: - YAML Validity

    @Test("Configuration is valid parseable YAML")
    func validYAML() throws {
        let config = DefaultConfigs.swiftlint
        let parsed = try Yams.load(yaml: config)

        #expect(parsed != nil, "YAML should parse successfully")
        #expect(parsed is [String: Any], "Root should be a dictionary")
    }

    // MARK: - Required Sections

    @Test("Contains disabled_rules as array of strings")
    func disabledRulesSection() throws {
        let yaml = try parseSwiftLintConfig()

        let disabledRules = yaml["disabled_rules"]
        #expect(disabledRules != nil, "disabled_rules section must exist")
        #expect(disabledRules is [String], "disabled_rules must be array of strings")

        if let rules = disabledRules as? [String] {
            #expect(!rules.isEmpty, "disabled_rules should have at least one rule")
        }
    }

    @Test("Contains opt_in_rules as array of strings")
    func optInRulesSection() throws {
        let yaml = try parseSwiftLintConfig()

        let optInRules = yaml["opt_in_rules"]
        #expect(optInRules != nil, "opt_in_rules section must exist")
        #expect(optInRules is [String], "opt_in_rules must be array of strings")

        if let rules = optInRules as? [String] {
            #expect(!rules.isEmpty, "opt_in_rules should enable at least one rule")
        }
    }

    @Test("Contains excluded paths as array")
    func excludedSection() throws {
        let yaml = try parseSwiftLintConfig()

        let excluded = yaml["excluded"]
        #expect(excluded != nil, "excluded section must exist")
        #expect(excluded is [String], "excluded must be array of paths")
    }

    // MARK: - Critical Safety Rules

    @Test("Enables force_unwrapping detection")
    func forceUnwrappingEnabled() throws {
        let yaml = try parseSwiftLintConfig()

        guard let optInRules = yaml["opt_in_rules"] as? [String] else {
            Issue.record("opt_in_rules not found or wrong type")
            return
        }

        #expect(
            optInRules.contains("force_unwrapping"),
            "force_unwrapping must be enabled for safety",
        )
    }

    @Test("Enables implicitly_unwrapped_optional detection")
    func implicitlyUnwrappedEnabled() throws {
        let yaml = try parseSwiftLintConfig()

        guard let optInRules = yaml["opt_in_rules"] as? [String] else {
            Issue.record("opt_in_rules not found or wrong type")
            return
        }

        #expect(
            optInRules.contains("implicitly_unwrapped_optional"),
            "implicitly_unwrapped_optional must be enabled for safety",
        )
    }

    // MARK: - Line Length Configuration

    @Test("Line length has warning and error thresholds")
    func lineLengthConfiguration() throws {
        let yaml = try parseSwiftLintConfig()

        guard let lineLength = yaml["line_length"] as? [String: Any] else {
            Issue.record("line_length configuration not found or wrong type")
            return
        }

        #expect(lineLength["warning"] != nil, "line_length must have warning threshold")
        #expect(lineLength["error"] != nil, "line_length must have error threshold")

        if let warning = lineLength["warning"] as? Int,
           let error = lineLength["error"] as? Int {
            #expect(warning < error, "Warning threshold must be less than error")
            #expect(warning >= 80, "Warning should be at least 80 characters")
            #expect(error <= 250, "Error should be at most 250 characters")
        }
    }

    // MARK: - File Length Configuration

    @Test("File length has warning and error thresholds")
    func fileLengthConfiguration() throws {
        let yaml = try parseSwiftLintConfig()

        guard let fileLength = yaml["file_length"] as? [String: Any] else {
            Issue.record("file_length configuration not found or wrong type")
            return
        }

        #expect(fileLength["warning"] != nil, "file_length must have warning threshold")
        #expect(fileLength["error"] != nil, "file_length must have error threshold")
    }

    // MARK: - Complexity Configuration

    @Test("Cyclomatic complexity has thresholds")
    func cyclomaticComplexityConfiguration() throws {
        let yaml = try parseSwiftLintConfig()

        guard let complexity = yaml["cyclomatic_complexity"] as? [String: Any] else {
            Issue.record("cyclomatic_complexity configuration not found or wrong type")
            return
        }

        #expect(complexity["warning"] != nil, "cyclomatic_complexity must have warning")
        #expect(complexity["error"] != nil, "cyclomatic_complexity must have error")
    }

    // MARK: - Build Directory Exclusions

    @Test("Excludes standard build directories")
    func excludesBuildDirectories() throws {
        let yaml = try parseSwiftLintConfig()

        guard let excluded = yaml["excluded"] as? [String] else {
            Issue.record("excluded section not found or wrong type")
            return
        }

        #expect(excluded.contains(".build"), ".build must be excluded")
        #expect(excluded.contains(".swiftpm"), ".swiftpm must be excluded")
        #expect(excluded.contains("DerivedData"), "DerivedData must be excluded")
    }

    // MARK: - Reporter Configuration

    @Test("Uses xcode reporter for IDE integration")
    func usesXcodeReporter() throws {
        let yaml = try parseSwiftLintConfig()

        let reporter = yaml["reporter"] as? String
        #expect(reporter == "xcode", "Should use xcode reporter for IDE integration")
    }

    // MARK: Private

    // MARK: - Helper

    private func parseSwiftLintConfig() throws -> [String: Any] {
        let config = DefaultConfigs.swiftlint
        guard let parsed = try Yams.load(yaml: config) as? [String: Any] else {
            throw ConfigParseError.invalidStructure
        }
        return parsed
    }
}

// MARK: - ConfigParseError

private enum ConfigParseError: Error {
    case invalidStructure
}

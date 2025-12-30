// SwiftFormatConfigTests.swift
// Tests for swift-format (apple/swift-format) JSON configuration validity.
//
// ## Test Goals
// - Verify the swift-format configuration is valid JSON that can be parsed
// - Ensure required fields exist with correct types
// - Validate rule configurations are sensible for modern Swift
// - Confirm formatting options match project standards
//
// ## Why These Tests Matter
// Invalid swift-format configuration will cause builds to fail or format incorrectly.
// These tests catch configuration errors before they reach users.

import Foundation
import Testing

@testable import SwiftProjectKitCore

// MARK: - SwiftFormatConfigTests

@Suite("swift-format Configuration Tests")
struct SwiftFormatConfigTests {
    // MARK: Internal

    // MARK: - JSON Validity

    @Test("Configuration is valid parseable JSON")
    func validJSON() throws {
        let config = DefaultConfigs.swiftFormat
        let data = Data(config.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data)

        #expect(parsed is [String: Any], "Root should be a dictionary")
    }

    @Test("Configuration is non-empty")
    func configurationNotEmpty() {
        let config = DefaultConfigs.swiftFormat
        #expect(!config.isEmpty, "swift-format config must not be empty")
    }

    // MARK: - Required Top-Level Fields

    @Test("Contains version field")
    func containsVersion() throws {
        let json = try parseSwiftFormatConfig()

        let version = json["version"]
        #expect(version != nil, "version field must exist")
        #expect(version is Int, "version must be an integer")
        #expect(version as? Int == 1, "version should be 1")
    }

    @Test("Contains lineLength field")
    func containsLineLength() throws {
        let json = try parseSwiftFormatConfig()

        let lineLength = json["lineLength"]
        #expect(lineLength != nil, "lineLength field must exist")
        #expect(lineLength is Int, "lineLength must be an integer")

        if let length = lineLength as? Int {
            #expect(length == 120, "lineLength should be 120")
        }
    }

    @Test("Contains indentation configuration")
    func containsIndentation() throws {
        let json = try parseSwiftFormatConfig()

        let indentation = json["indentation"]
        #expect(indentation != nil, "indentation field must exist")
        #expect(indentation is [String: Any], "indentation must be a dictionary")

        if let indent = indentation as? [String: Any] {
            #expect(indent["spaces"] as? Int == 4, "Should use 4-space indentation")
        }
    }

    @Test("Contains tabWidth field")
    func containsTabWidth() throws {
        let json = try parseSwiftFormatConfig()

        let tabWidth = json["tabWidth"]
        #expect(tabWidth != nil, "tabWidth field must exist")
        #expect(tabWidth as? Int == 4, "tabWidth should be 4")
    }

    @Test("Contains maximumBlankLines field")
    func containsMaximumBlankLines() throws {
        let json = try parseSwiftFormatConfig()

        let maxBlankLines = json["maximumBlankLines"]
        #expect(maxBlankLines != nil, "maximumBlankLines field must exist")
        #expect(maxBlankLines as? Int == 1, "maximumBlankLines should be 1")
    }

    // MARK: - Rules Configuration

    @Test("Contains rules dictionary")
    func containsRules() throws {
        let json = try parseSwiftFormatConfig()

        let rules = json["rules"]
        #expect(rules != nil, "rules section must exist")
        #expect(rules is [String: Bool], "rules must be dictionary of booleans")
    }

    @Test("Rules are all boolean values")
    func rulesAreBooleans() throws {
        let json = try parseSwiftFormatConfig()

        guard let rules = json["rules"] as? [String: Any] else {
            Issue.record("rules section not found or wrong type")
            return
        }

        for (key, value) in rules {
            #expect(value is Bool, "Rule '\(key)' value must be boolean")
        }
    }

    // MARK: - Critical Safety Rules

    @Test("NeverForceUnwrap rule is enabled")
    func neverForceUnwrapEnabled() throws {
        let rules = try parseRules()

        #expect(
            rules["NeverForceUnwrap"] == true,
            "NeverForceUnwrap must be enabled for safety"
        )
    }

    @Test("NeverUseForceTry rule is enabled")
    func neverUseForceTryEnabled() throws {
        let rules = try parseRules()

        #expect(
            rules["NeverUseForceTry"] == true,
            "NeverUseForceTry must be enabled for safety"
        )
    }

    @Test("NeverUseImplicitlyUnwrappedOptionals rule is enabled")
    func neverUseImplicitlyUnwrappedOptionalsEnabled() throws {
        let rules = try parseRules()

        #expect(
            rules["NeverUseImplicitlyUnwrappedOptionals"] == true,
            "NeverUseImplicitlyUnwrappedOptionals must be enabled for safety"
        )
    }

    // MARK: - Code Style Rules

    @Test("OrderedImports rule is enabled")
    func orderedImportsEnabled() throws {
        let rules = try parseRules()

        #expect(
            rules["OrderedImports"] == true,
            "OrderedImports should be enabled for consistency"
        )
    }

    @Test("DoNotUseSemicolons rule is enabled")
    func doNotUseSemicolonsEnabled() throws {
        let rules = try parseRules()

        #expect(
            rules["DoNotUseSemicolons"] == true,
            "DoNotUseSemicolons should be enabled"
        )
    }

    @Test("UseEarlyExits rule is enabled")
    func useEarlyExitsEnabled() throws {
        let rules = try parseRules()

        #expect(
            rules["UseEarlyExits"] == true,
            "UseEarlyExits should be enabled for cleaner control flow"
        )
    }

    @Test("FileScopedDeclarationPrivacy rule is enabled")
    func fileScopedDeclarationPrivacyEnabled() throws {
        let rules = try parseRules()

        #expect(
            rules["FileScopedDeclarationPrivacy"] == true,
            "FileScopedDeclarationPrivacy should be enabled"
        )
    }

    // MARK: - Documentation Rules

    @Test("AllPublicDeclarationsHaveDocumentation is disabled")
    func allPublicDeclarationsHaveDocumentationDisabled() throws {
        let rules = try parseRules()

        #expect(
            rules["AllPublicDeclarationsHaveDocumentation"] == false,
            "AllPublicDeclarationsHaveDocumentation should be disabled (too strict)"
        )
    }

    // MARK: - Formatting Options

    @Test("respectsExistingLineBreaks is enabled")
    func respectsExistingLineBreaksEnabled() throws {
        let json = try parseSwiftFormatConfig()

        #expect(
            json["respectsExistingLineBreaks"] as? Bool == true,
            "respectsExistingLineBreaks should be true"
        )
    }

    @Test("lineBreakBeforeEachArgument is enabled")
    func lineBreakBeforeEachArgumentEnabled() throws {
        let json = try parseSwiftFormatConfig()

        #expect(
            json["lineBreakBeforeEachArgument"] as? Bool == true,
            "lineBreakBeforeEachArgument should be true"
        )
    }

    @Test("multiElementCollectionTrailingCommas is enabled")
    func multiElementCollectionTrailingCommasEnabled() throws {
        let json = try parseSwiftFormatConfig()

        #expect(
            json["multiElementCollectionTrailingCommas"] as? Bool == true,
            "multiElementCollectionTrailingCommas should be true"
        )
    }

    @Test("fileScopedDeclarationPrivacy has correct accessLevel")
    func fileScopedDeclarationPrivacyAccessLevel() throws {
        let json = try parseSwiftFormatConfig()

        guard let privacy = json["fileScopedDeclarationPrivacy"] as? [String: Any] else {
            Issue.record("fileScopedDeclarationPrivacy not found or wrong type")
            return
        }

        #expect(
            privacy["accessLevel"] as? String == "private",
            "fileScopedDeclarationPrivacy.accessLevel should be 'private'"
        )
    }

    // MARK: Private

    // MARK: - Helpers

    private func parseSwiftFormatConfig() throws -> [String: Any] {
        let config = DefaultConfigs.swiftFormat
        let data = Data(config.utf8)
        guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigParseError.invalidStructure
        }
        return parsed
    }

    private func parseRules() throws -> [String: Bool] {
        let json = try parseSwiftFormatConfig()
        guard let rules = json["rules"] as? [String: Bool] else {
            throw ConfigParseError.invalidStructure
        }
        return rules
    }
}

// MARK: - ConfigParseError

private enum ConfigParseError: Error {
    case invalidStructure
}

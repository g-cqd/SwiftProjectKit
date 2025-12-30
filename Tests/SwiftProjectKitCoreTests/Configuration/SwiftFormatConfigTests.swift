// SwiftFormatConfigTests.swift
// Tests for SwiftFormat configuration template validity and structure.
//
// ## Test Goals
// - Verify the SwiftFormat configuration can be parsed as valid options
// - Ensure critical formatting options are set correctly
// - Validate exclusion patterns are properly configured
// - Confirm Swift version is specified
//
// ## Why These Tests Matter
// Invalid SwiftFormat configuration will cause formatting to fail or produce
// unexpected results. These tests ensure the configuration is valid and sensible.

import Foundation
@testable import SwiftProjectKitCore
import Testing

@Suite("SwiftFormat Configuration Tests")
struct SwiftFormatConfigTests {
    // MARK: Internal

    // MARK: - Basic Validity

    @Test("Configuration is non-empty")
    func configurationNotEmpty() {
        let config = DefaultConfigs.swiftformat
        #expect(!config.isEmpty, "SwiftFormat config must not be empty")
    }

    @Test("Configuration has multiple lines")
    func configurationHasMultipleLines() {
        let config = DefaultConfigs.swiftformat
        let lines = config.components(separatedBy: .newlines).filter { !$0.isEmpty }
        #expect(lines.count > 5, "Config should have multiple option lines")
    }

    // MARK: - Swift Version

    @Test("Specifies Swift version")
    func specifiesSwiftVersion() throws {
        let options = try parseSwiftFormatOptions()

        #expect(
            options.contains { $0.key == "--swiftversion" },
            "Must specify --swiftversion for correct parsing",
        )
    }

    @Test("Swift version is valid format")
    func swiftVersionFormat() throws {
        let options = try parseSwiftFormatOptions()

        guard let version = options["--swiftversion"] else {
            Issue.record("--swiftversion not found")
            return
        }

        let versionPattern = #"^\d+\.\d+$"#
        let regex = try NSRegularExpression(pattern: versionPattern)
        let range = NSRange(version.startIndex..., in: version)

        #expect(
            regex.firstMatch(in: version, range: range) != nil,
            "Swift version '\(version)' should be in X.Y format",
        )
    }

    // MARK: - Indentation

    @Test("Specifies indentation setting")
    func specifiesIndentation() throws {
        let options = try parseSwiftFormatOptions()

        #expect(
            options.contains { $0.key == "--indent" },
            "Must specify --indent for consistent formatting",
        )
    }

    @Test("Uses 4-space indentation")
    func uses4SpaceIndentation() throws {
        let options = try parseSwiftFormatOptions()

        let indent = options["--indent"]
        #expect(indent == "4", "Should use 4-space indentation (industry standard)")
    }

    // MARK: - Line Width

    @Test("Specifies maximum line width")
    func specifiesMaxWidth() throws {
        let options = try parseSwiftFormatOptions()

        #expect(
            options.contains { $0.key == "--maxwidth" },
            "Must specify --maxwidth for line length control",
        )
    }

    @Test("Max width matches SwiftLint line_length")
    func maxWidthMatchesSwiftLint() throws {
        let options = try parseSwiftFormatOptions()

        guard let maxWidth = options["--maxwidth"], let width = Int(maxWidth) else {
            Issue.record("--maxwidth not found or not a number")
            return
        }

        #expect(
            width == 120,
            "Max width should be 120 to match SwiftLint line_length warning",
        )
    }

    // MARK: - Line Breaks

    @Test("Specifies line break style")
    func specifiesLineBreaks() throws {
        let options = try parseSwiftFormatOptions()

        #expect(
            options.contains { $0.key == "--linebreaks" },
            "Should specify --linebreaks for consistency",
        )
    }

    @Test("Uses LF line breaks")
    func usesLFLineBreaks() throws {
        let options = try parseSwiftFormatOptions()

        let linebreaks = options["--linebreaks"]
        #expect(linebreaks == "lf", "Should use Unix-style LF line breaks")
    }

    // MARK: - Whitespace

    @Test("Specifies whitespace trimming")
    func specifiesWhitespaceTrimming() throws {
        let options = try parseSwiftFormatOptions()

        #expect(
            options.contains { $0.key == "--trimwhitespace" },
            "Should specify --trimwhitespace",
        )
    }

    // MARK: - Exclusions

    @Test("Excludes build directories")
    func excludesBuildDirectories() throws {
        let options = try parseSwiftFormatOptions()

        guard let excludes = options["--exclude"] else {
            Issue.record("--exclude not found")
            return
        }

        #expect(excludes.contains(".build"), ".build must be excluded")
        #expect(excludes.contains(".swiftpm"), ".swiftpm must be excluded")
        #expect(excludes.contains("DerivedData"), "DerivedData must be excluded")
    }

    // MARK: - Enabled Rules

    @Test("Enables blankLineAfterImports")
    func enablesBlankLineAfterImports() throws {
        let options = try parseSwiftFormatOptions()

        guard let enabled = options["--enable"] else {
            Issue.record("--enable not found")
            return
        }

        #expect(
            enabled.contains("blankLineAfterImports"),
            "blankLineAfterImports should be enabled",
        )
    }

    @Test("Enables isEmpty rule")
    func enablesIsEmpty() throws {
        let options = try parseSwiftFormatOptions()

        guard let enabled = options["--enable"] else {
            Issue.record("--enable not found")
            return
        }

        #expect(enabled.contains("isEmpty"), "isEmpty should be enabled")
    }

    // MARK: - Import Grouping

    @Test("Specifies import grouping")
    func specifiesImportGrouping() throws {
        let options = try parseSwiftFormatOptions()

        #expect(
            options.contains { $0.key == "--importgrouping" },
            "Should specify --importgrouping for organized imports",
        )
    }

    // MARK: Private

    // MARK: - Helper

    private func parseSwiftFormatOptions() throws -> [String: String] {
        let config = DefaultConfigs.swiftformat
        var options: [String: String] = [:]

        let lines = config.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            if trimmed.hasPrefix("--") {
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                let key = String(parts[0])

                if parts.count > 1 {
                    let existingValue = options[key] ?? ""
                    let newValue = String(parts[1])
                    options[key] = existingValue.isEmpty ? newValue : "\(existingValue),\(newValue)"
                } else {
                    options[key] = ""
                }
            }
        }

        return options
    }
}

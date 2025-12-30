// SwiftProjectKitCoreTests.swift
// Tests for core module constants and exports.
//
// ## Test Goals
// - Verify version constant is properly formatted
// - Ensure default Swift version is current and valid
// - Validate default Xcode version is current
// - Test that Foundation is re-exported
//
// ## Why These Tests Matter
// These constants drive project scaffolding and CI workflows.
// Invalid versions cause build failures and incorrect configurations.

import Foundation
@testable import SwiftProjectKitCore
import Testing

@Suite("SwiftProjectKitCore Module Tests")
struct SwiftProjectKitCoreModuleTests {
    // MARK: - Version Constant

    @Test("Version constant is non-empty")
    func versionIsNonEmpty() {
        #expect(!swiftProjectKitVersion.isEmpty, "Version must not be empty")
    }

    @Test("Version is semantic versioning format")
    func versionIsSemanticFormat() {
        let semverPattern = #"^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?$"#

        let regex = try? NSRegularExpression(pattern: semverPattern)
        let range = NSRange(swiftProjectKitVersion.startIndex..., in: swiftProjectKitVersion)
        let match = regex?.firstMatch(in: swiftProjectKitVersion, range: range)

        #expect(
            match != nil,
            "Version '\(swiftProjectKitVersion)' should be semantic versioning (X.Y.Z)",
        )
    }

    // MARK: - Swift Version

    @Test("Default Swift version is non-empty")
    func defaultSwiftVersionIsNonEmpty() {
        #expect(!defaultSwiftVersion.isEmpty, "Default Swift version must not be empty")
    }

    @Test("Default Swift version is valid format")
    func defaultSwiftVersionIsValidFormat() {
        let versionPattern = #"^\d+\.\d+$"#

        let regex = try? NSRegularExpression(pattern: versionPattern)
        let range = NSRange(defaultSwiftVersion.startIndex..., in: defaultSwiftVersion)
        let match = regex?.firstMatch(in: defaultSwiftVersion, range: range)

        #expect(
            match != nil,
            "Swift version '\(defaultSwiftVersion)' should be X.Y format",
        )
    }

    @Test("Default Swift version is 6.2")
    func defaultSwiftVersionIsCurrent() {
        #expect(defaultSwiftVersion == "6.2", "Default Swift version should be 6.2")
    }

    // MARK: - Xcode Version

    @Test("Default Xcode version is non-empty")
    func defaultXcodeVersionIsNonEmpty() {
        #expect(!defaultXcodeVersion.isEmpty, "Default Xcode version must not be empty")
    }

    @Test("Default Xcode version is valid format")
    func defaultXcodeVersionIsValidFormat() {
        let versionPattern = #"^\d+(\.\d+)*$"#

        let regex = try? NSRegularExpression(pattern: versionPattern)
        let range = NSRange(defaultXcodeVersion.startIndex..., in: defaultXcodeVersion)
        let match = regex?.firstMatch(in: defaultXcodeVersion, range: range)

        #expect(
            match != nil,
            "Xcode version '\(defaultXcodeVersion)' should be numeric format",
        )
    }

    // MARK: - Foundation Re-export

    @Test("Foundation types are accessible via @_exported")
    func foundationTypesAccessible() {
        let url = URL(fileURLWithPath: "/test")
        let data = Data()
        let uuid = UUID()

        #expect(url.path == "/test")
        #expect(data.isEmpty)
        #expect(!uuid.uuidString.isEmpty)
    }
}

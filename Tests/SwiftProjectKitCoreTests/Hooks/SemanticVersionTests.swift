//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Testing

@testable import SwiftProjectKitCore

@Suite("SemanticVersion Tests")
struct SemanticVersionTests {

    // MARK: - Parsing Tests

    @Test("Parse simple version")
    func parseSimpleVersion() {
        let version = SemanticVersion(string: "1.2.3")
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 2)
        #expect(version?.patch == 3)
        #expect(version?.preRelease == nil)
        #expect(version?.buildMetadata == nil)
    }

    @Test("Parse version with pre-release")
    func parseVersionWithPreRelease() {
        let version = SemanticVersion(string: "1.2.3-beta.1")
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 2)
        #expect(version?.patch == 3)
        #expect(version?.preRelease == "beta.1")
        #expect(version?.buildMetadata == nil)
    }

    @Test("Parse version with build metadata")
    func parseVersionWithBuildMetadata() {
        let version = SemanticVersion(string: "1.2.3+build.123")
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 2)
        #expect(version?.patch == 3)
        #expect(version?.preRelease == nil)
        #expect(version?.buildMetadata == "build.123")
    }

    @Test("Parse full version")
    func parseFullVersion() {
        let version = SemanticVersion(string: "1.2.3-alpha.1+build.456")
        #expect(version != nil)
        #expect(version?.major == 1)
        #expect(version?.minor == 2)
        #expect(version?.patch == 3)
        #expect(version?.preRelease == "alpha.1")
        #expect(version?.buildMetadata == "build.456")
    }

    @Test("Parse invalid version returns nil")
    func parseInvalidVersion() {
        #expect(SemanticVersion(string: "invalid") == nil)
        #expect(SemanticVersion(string: "1.2") == nil)
        #expect(SemanticVersion(string: "1.2.3.4") == nil)
        #expect(SemanticVersion(string: "v1.2.3") == nil)
        #expect(SemanticVersion(string: "") == nil)
    }

    @Test("Parse version with whitespace")
    func parseVersionWithWhitespace() {
        let version = SemanticVersion(string: "  1.2.3  ")
        #expect(version != nil)
        #expect(version?.major == 1)
    }

    // MARK: - Description Tests

    @Test("Description for simple version")
    func descriptionSimple() {
        let version = SemanticVersion(major: 1, minor: 2, patch: 3)
        #expect(version.description == "1.2.3")
    }

    @Test("Description for version with pre-release")
    func descriptionWithPreRelease() {
        let version = SemanticVersion(major: 1, minor: 2, patch: 3, preRelease: "beta.1")
        #expect(version.description == "1.2.3-beta.1")
    }

    @Test("Description for full version")
    func descriptionFull() {
        let version = SemanticVersion(
            major: 1,
            minor: 2,
            patch: 3,
            preRelease: "alpha",
            buildMetadata: "build.123"
        )
        #expect(version.description == "1.2.3-alpha+build.123")
    }

    @Test("Core version excludes pre-release and build")
    func coreVersion() {
        let version = SemanticVersion(
            major: 1,
            minor: 2,
            patch: 3,
            preRelease: "alpha",
            buildMetadata: "build.123"
        )
        #expect(version.coreVersion == "1.2.3")
    }

    // MARK: - Bump Tests

    @Test("Bump major resets minor and patch")
    func bumpMajor() {
        let version = SemanticVersion(major: 1, minor: 2, patch: 3)
        let bumped = version.bumpMajor()
        #expect(bumped.major == 2)
        #expect(bumped.minor == 0)
        #expect(bumped.patch == 0)
    }

    @Test("Bump minor resets patch")
    func bumpMinor() {
        let version = SemanticVersion(major: 1, minor: 2, patch: 3)
        let bumped = version.bumpMinor()
        #expect(bumped.major == 1)
        #expect(bumped.minor == 3)
        #expect(bumped.patch == 0)
    }

    @Test("Bump patch")
    func bumpPatch() {
        let version = SemanticVersion(major: 1, minor: 2, patch: 3)
        let bumped = version.bumpPatch()
        #expect(bumped.major == 1)
        #expect(bumped.minor == 2)
        #expect(bumped.patch == 4)
    }

    // MARK: - Comparison Tests

    @Test("Version comparison by major")
    func compareByMajor() {
        let v1 = SemanticVersion(major: 1, minor: 0, patch: 0)
        let v2 = SemanticVersion(major: 2, minor: 0, patch: 0)
        #expect(v1 < v2)
    }

    @Test("Version comparison by minor")
    func compareByMinor() {
        let v1 = SemanticVersion(major: 1, minor: 0, patch: 0)
        let v2 = SemanticVersion(major: 1, minor: 1, patch: 0)
        #expect(v1 < v2)
    }

    @Test("Version comparison by patch")
    func compareByPatch() {
        let v1 = SemanticVersion(major: 1, minor: 0, patch: 0)
        let v2 = SemanticVersion(major: 1, minor: 0, patch: 1)
        #expect(v1 < v2)
    }

    @Test("Pre-release version is less than release")
    func preReleaseLessThanRelease() {
        let preRelease = SemanticVersion(major: 1, minor: 0, patch: 0, preRelease: "alpha")
        let release = SemanticVersion(major: 1, minor: 0, patch: 0)
        #expect(preRelease < release)
    }

    @Test("Equal versions")
    func equalVersions() {
        let v1 = SemanticVersion(major: 1, minor: 2, patch: 3)
        let v2 = SemanticVersion(major: 1, minor: 2, patch: 3)
        #expect(v1 == v2)
    }
}

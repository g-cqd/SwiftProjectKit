// CIWorkflowTests.swift
// Tests for GitHub Actions CI workflow template validity and structure.
//
// ## Test Goals
// - Verify generated workflows are valid YAML
// - Ensure required jobs and steps are present
// - Validate triggers and permissions are correct
// - Test platform matrix generation
// - Verify release workflow integration
// - Test binary release features (universal binary, packaging, checksums)
// - Validate auto-release on main functionality
// - Ensure custom binary names work correctly
//
// ## Why These Tests Matter
// Invalid GitHub Actions workflows will fail CI. These tests ensure
// generated workflows are valid and complete before they reach users.
// Binary release features are critical for CLI tool distribution.

import Foundation
@testable import SwiftProjectKitCore
import Testing
import Yams

// MARK: - CIWorkflowTests

// swiftlint:disable type_body_length
@Suite("CI Workflow Tests")
struct CIWorkflowTests {
    // MARK: Internal

    // MARK: - YAML Validity

    @Test("Generated workflow is valid YAML")
    func validYAML() throws {
        let workflow = DefaultConfigs.ciWorkflow(name: "TestPackage", platforms: .macOSOnly)
        let parsed = try Yams.load(yaml: workflow)

        #expect(parsed != nil, "Workflow YAML should parse successfully")
        #expect(parsed is [String: Any], "Root should be a dictionary")
    }

    @Test("Workflow with all options is valid YAML")
    func validYAMLWithAllOptions() throws {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .allPlatforms,
            includeRelease: true,
            includePlatformMatrix: true,
        )
        let parsed = try Yams.load(yaml: workflow)

        #expect(parsed != nil, "Complex workflow YAML should parse successfully")
    }

    // MARK: - Basic Structure

    @Test("Has workflow name")
    func hasWorkflowName() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        #expect(yaml["name"] != nil, "Workflow must have a name")
        #expect(yaml["name"] as? String == "CI/CD", "Workflow should be named 'CI/CD'")
    }

    @Test("Has on triggers")
    func hasOnTriggers() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        let on = yaml["on"]
        #expect(on != nil, "Workflow must have 'on' triggers")
        #expect(on is [String: Any], "'on' should be a dictionary")
    }

    @Test("Has jobs section")
    func hasJobsSection() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        let jobs = yaml["jobs"]
        #expect(jobs != nil, "Workflow must have 'jobs' section")
        #expect(jobs is [String: Any], "'jobs' should be a dictionary")
    }

    // MARK: - Triggers

    @Test("Triggers on push to main")
    func triggersOnPushToMain() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        guard let on = yaml["on"] as? [String: Any],
              let push = on["push"] as? [String: Any],
              let branches = push["branches"] as? [String]
        else {
            Issue.record("Push trigger configuration not found")
            return
        }

        #expect(branches.contains("main"), "Should trigger on push to main")
    }

    @Test("Triggers on pull requests")
    func triggersOnPullRequests() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        guard let on = yaml["on"] as? [String: Any] else {
            Issue.record("'on' section not found")
            return
        }

        #expect(on["pull_request"] != nil, "Should trigger on pull requests")
    }

    // MARK: - Concurrency Control

    @Test("Has concurrency configuration")
    func hasConcurrencyConfig() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        let concurrency = yaml["concurrency"]
        #expect(concurrency != nil, "Should have concurrency configuration")
        #expect(concurrency is [String: Any], "Concurrency should be a dictionary")
    }

    @Test("Concurrency cancels in-progress for PRs only")
    func concurrencyCancelsForPRsOnly() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        guard let concurrency = yaml["concurrency"] as? [String: Any] else {
            Issue.record("Concurrency configuration not found")
            return
        }

        let cancelInProgress = concurrency["cancel-in-progress"]
        #expect(cancelInProgress != nil, "Should have cancel-in-progress setting")
    }

    // MARK: - Jobs

    @Test("Has lint job")
    func hasLintJob() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["lint"] != nil, "Should have lint job")
    }

    @Test("Has build-and-test job")
    func hasBuildAndTestJob() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["build-and-test"] != nil, "Should have build-and-test job")
    }

    // MARK: - Lint Job Steps

    @Test("Lint job runs SwiftLint")
    func lintJobRunsSwiftLint() throws {
        let workflow = DefaultConfigs.ciWorkflow(name: "TestPackage", platforms: .macOSOnly)

        #expect(workflow.contains("swiftlint"), "Lint job should run SwiftLint")
    }

    @Test("Lint job runs SwiftFormat")
    func lintJobRunsSwiftFormat() throws {
        let workflow = DefaultConfigs.ciWorkflow(name: "TestPackage", platforms: .macOSOnly)

        #expect(workflow.contains("swiftformat"), "Lint job should run SwiftFormat")
    }

    // MARK: - Build Job

    @Test("Build job runs swift build")
    func buildJobRunsSwiftBuild() throws {
        let workflow = DefaultConfigs.ciWorkflow(name: "TestPackage", platforms: .macOSOnly)

        #expect(workflow.contains("swift build"), "Should run swift build")
    }

    @Test("Build job runs swift test")
    func buildJobRunsSwiftTest() throws {
        let workflow = DefaultConfigs.ciWorkflow(name: "TestPackage", platforms: .macOSOnly)

        #expect(workflow.contains("swift test"), "Should run swift test")
    }

    // MARK: - Xcode Selection

    @Test("Selects Xcode version")
    func selectsXcodeVersion() throws {
        let workflow = DefaultConfigs.ciWorkflow(name: "TestPackage", platforms: .macOSOnly)

        #expect(workflow.contains("xcode-select"), "Should select Xcode version")
    }

    // MARK: - Single Platform (No Matrix)

    @Test("Single platform has no matrix strategy")
    func singlePlatformNoMatrix() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(
            jobs["build-platforms"] == nil,
            "macOS-only should not have platform matrix job",
        )
    }

    // MARK: - Platform Matrix

    @Test("Multiple platforms with matrix flag creates matrix job")
    func multiplePlatformsWithMatrixFlagCreatesMatrixJob() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .allPlatforms,
            includePlatformMatrix: true,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(
            jobs["build-platforms"] != nil,
            "Should have build-platforms job when matrix requested",
        )
    }

    @Test("Platform matrix excludes disabled platforms")
    func platformMatrixExcludesDisabledPlatforms() throws {
        let iOSMacOS = PlatformConfiguration(
            iOS: "18.0",
            macOS: "15.0",
            watchOS: nil,
            tvOS: nil,
            visionOS: nil,
        )

        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: iOSMacOS,
            includePlatformMatrix: true,
        )

        #expect(workflow.contains("platform: iOS"), "Should include iOS")
        #expect(workflow.contains("platform: macOS"), "Should include macOS")
        #expect(!workflow.contains("platform: tvOS"), "Should NOT include tvOS")
        #expect(!workflow.contains("platform: watchOS"), "Should NOT include watchOS")
        #expect(!workflow.contains("platform: visionOS"), "Should NOT include visionOS")
    }

    @Test("Platform matrix is opt-in by default")
    func platformMatrixIsOptIn() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .allPlatforms,
            includePlatformMatrix: false,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(
            jobs["build-platforms"] == nil,
            "Platform matrix should be opt-in",
        )
    }

    // MARK: - Package Name Usage

    @Test("Uses package name in xcodebuild scheme")
    func usesPackageNameInScheme() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "MyAwesomePackage",
            platforms: .allPlatforms,
            includePlatformMatrix: true,
        )

        #expect(
            workflow.contains("-scheme MyAwesomePackage"),
            "Should use package name in xcodebuild scheme",
        )
    }

    // MARK: - Release Support

    @Test("Release workflow includes tag triggers")
    func releaseIncludesTagTriggers() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
        )

        guard let on = yaml["on"] as? [String: Any],
              let push = on["push"] as? [String: Any]
        else {
            Issue.record("Push trigger not found")
            return
        }

        #expect(push["tags"] != nil, "Release workflow should trigger on tags")
    }

    @Test("Release workflow has validate-release job")
    func releaseHasValidateJob() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(
            jobs["validate-release"] != nil,
            "Release workflow should have validate-release job",
        )
    }

    @Test("Release workflow has changelog job")
    func releaseHasChangelogJob() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(
            jobs["changelog"] != nil,
            "Release workflow should have changelog job",
        )
    }

    @Test("Release workflow has release job")
    func releaseHasReleaseJob() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(
            jobs["release"] != nil,
            "Release workflow should have release job",
        )
    }

    @Test("Release workflow has write permissions")
    func releaseHasWritePermissions() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
        )

        let permissions = yaml["permissions"]
        #expect(permissions != nil, "Release workflow should have permissions")
    }

    @Test("Non-release workflow excludes release jobs")
    func nonReleaseExcludesReleaseJobs() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: false,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["validate-release"] == nil, "Should not have validate-release job")
        #expect(jobs["changelog"] == nil, "Should not have changelog job")
        #expect(jobs["release"] == nil, "Should not have release job")
    }

    // MARK: - Binary Release

    @Test("Binary release workflow is valid YAML")
    func binaryReleaseWorkflowIsValidYAML() throws {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
        )
        let parsed = try Yams.load(yaml: workflow)

        #expect(parsed != nil, "Binary release workflow should be valid YAML")
    }

    @Test("Binary release workflow builds universal binary")
    func binaryReleaseBuildUniversal() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
        )

        #expect(workflow.contains("Build Universal Binary"), "Should have universal binary build step")
        #expect(workflow.contains("--arch arm64"), "Should build for ARM64")
        #expect(workflow.contains("--arch x86_64"), "Should build for x86_64")
        #expect(workflow.contains("lipo -create"), "Should use lipo to create universal binary")
    }

    @Test("Binary release workflow packages binaries")
    func binaryReleasePackagesBinaries() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
        )

        #expect(workflow.contains("Package Binaries"), "Should have package binaries step")
        #expect(workflow.contains("tar -C release -czvf"), "Should create tar.gz archives")
        #expect(workflow.contains("shasum -a 256"), "Should generate checksums")
    }

    @Test("Binary release workflow uploads artifacts")
    func binaryReleaseUploadsArtifacts() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
            binaryName: "spk",
        )

        #expect(
            workflow.contains("spk-${{ needs.validate-release.outputs.version }}-macos-"),
            "Should upload versioned binaries",
        )
        #expect(workflow.contains("checksums.txt"), "Should upload checksums")
    }

    @Test("Binary release uses custom binary name")
    func binaryReleaseUsesCustomBinaryName() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "MyProject",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
            binaryName: "mytool",
        )

        #expect(workflow.contains("mytool-arm64"), "Should use custom binary name for ARM64")
        #expect(workflow.contains("mytool-x86_64"), "Should use custom binary name for x86_64")
        #expect(workflow.contains("mytool-${VERSION}-macos"), "Should use custom name in archives")
    }

    @Test("Binary release defaults binary name to lowercase project name")
    func binaryReleaseDefaultsBinaryName() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "MyProject",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
        )

        #expect(workflow.contains("myproject-arm64"), "Should default to lowercase project name")
    }

    @Test("Binary release includes pre-built binary installation instructions")
    func binaryReleaseIncludesInstallInstructions() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
            binaryName: "spk",
        )

        #expect(workflow.contains("Pre-built Binary (macOS)"), "Should have binary install section")
        #expect(workflow.contains("curl -L"), "Should have curl download command")
        #expect(workflow.contains("sudo mv"), "Should have install command")
    }

    @Test("Non-binary release excludes binary building steps")
    func nonBinaryReleaseExcludesBinarySteps() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: false,
        )

        #expect(!workflow.contains("Build Universal Binary"), "Should not have universal binary step")
        #expect(!workflow.contains("Package Binaries"), "Should not have package binaries step")
        #expect(!workflow.contains("lipo -create"), "Should not use lipo")
    }

    // MARK: - Auto Release on Main

    @Test("Auto release on main includes push to main trigger")
    func autoReleaseOnMainIncludesPushTrigger() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            autoReleaseOnMain: true,
        )

        #expect(
            workflow.contains("github.ref == 'refs/heads/main'"),
            "Should check for push to main",
        )
        #expect(
            workflow.contains("[skip release]"),
            "Should support [skip release] in commit message",
        )
        #expect(
            workflow.contains("github-actions"),
            "Should skip bot commits",
        )
    }

    @Test("Auto release on main has correct validate-release condition")
    func autoReleaseOnMainValidateCondition() throws {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            autoReleaseOnMain: true,
        )

        #expect(
            workflow.contains("push to main"),
            "Stage comment should mention push to main",
        )
    }

    @Test("Non-auto-release excludes push to main trigger in validate-release")
    func nonAutoReleaseExcludesPushTrigger() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            autoReleaseOnMain: false,
        )

        #expect(
            !workflow.contains("[skip release]"),
            "Should not check for skip release commit",
        )
    }

    @Test("Auto release creates tag on push to main")
    func autoReleaseCreatesTagOnPushToMain() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
            autoReleaseOnMain: true,
        )

        #expect(
            workflow.contains("github.event_name == 'push' && github.ref == 'refs/heads/main'"),
            "Should create tag on push to main",
        )
    }

    // MARK: - Full Binary Release Workflow

    @Test("Full binary release workflow with all options is valid")
    func fullBinaryReleaseWorkflowIsValid() throws {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "SwiftProjectKit",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
            binaryName: "spk",
            autoReleaseOnMain: true,
        )

        let parsed = try Yams.load(yaml: workflow) as? [String: Any]
        #expect(parsed != nil, "Full workflow should be valid YAML")

        guard let jobs = parsed?["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["lint"] != nil, "Should have lint job")
        #expect(jobs["build-and-test"] != nil, "Should have build-and-test job")
        #expect(jobs["codeql"] != nil, "Should have codeql job")
        #expect(jobs["validate-release"] != nil, "Should have validate-release job")
        #expect(jobs["changelog"] != nil, "Should have changelog job")
        #expect(jobs["release"] != nil, "Should have release job")
    }

    // MARK: Private

    // MARK: - Helpers

    private func parseWorkflow(
        name: String,
        platforms: PlatformConfiguration,
        includeRelease: Bool = false,
        includePlatformMatrix: Bool = false,
        includeBinaryRelease: Bool = false,
        binaryName: String? = nil,
        autoReleaseOnMain: Bool = false,
    ) throws -> [String: Any] {
        let workflow = DefaultConfigs.ciWorkflow(
            name: name,
            platforms: platforms,
            includeRelease: includeRelease,
            includePlatformMatrix: includePlatformMatrix,
            includeBinaryRelease: includeBinaryRelease,
            binaryName: binaryName,
            autoReleaseOnMain: autoReleaseOnMain,
        )

        guard let parsed = try Yams.load(yaml: workflow) as? [String: Any] else {
            throw WorkflowParseError.invalidStructure
        }

        return parsed
    }
}

// swiftlint:enable type_body_length

// MARK: - WorkflowParseError

private enum WorkflowParseError: Error {
    case invalidStructure
}

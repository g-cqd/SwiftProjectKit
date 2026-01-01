// CIWorkflowTests.swift
// Tests for GitHub Actions CI workflow template validity and structure.
//
// ## Test Goals
// - Verify generated workflows are valid YAML
// - Ensure required jobs and steps are present
// - Validate triggers and permissions are correct
// - Test platform matrix generation
// - Verify release workflow integration with VERSION file
// - Test tag existence check to prevent duplicate releases
// - Test binary release features (universal binary, packaging, checksums)
// - Validate Homebrew formula generation
// - Ensure custom binary names work correctly
// - Test static analysis (SWA) integration
// - Test documentation generation and deployment
// - Verify coverage report generation (lcov + text)
//
// ## Release Flow
// The release workflow uses a VERSION file as single source of truth:
// 1. prepare-release job reads VERSION and checks if tag exists
// 2. If tag exists, should_release=false and release job is skipped
// 3. If new version, should_release=true, release job creates tag and release
//
// ## Why These Tests Matter
// Invalid GitHub Actions workflows will fail CI. These tests ensure
// generated workflows are valid and complete before they reach users.
// Binary release features are critical for CLI tool distribution.

import Foundation
import Testing
import Yams

@testable import SwiftProjectKitCore

// MARK: - CIWorkflowTests

// swa:ignore-type-length
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

    @Test("Has format-check job")
    func hasFormatCheckJob() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["format-check"] != nil, "Should have format-check job")
    }

    @Test("Has test job")
    func hasTestJob() throws {
        let yaml = try parseWorkflow(name: "TestPackage", platforms: .macOSOnly)

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["test"] != nil, "Should have test job")
    }

    // MARK: - Format Check Job Steps

    @Test("Format check job runs swift-format")
    func formatCheckJobRunsSwiftFormat() throws {
        let workflow = DefaultConfigs.ciWorkflow(name: "TestPackage", platforms: .macOSOnly)

        #expect(workflow.contains("swift format lint"), "Format check job should run swift format")
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

    @Test("Release workflow has prepare-release job")
    func releaseHasPrepareJob() throws {
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
            jobs["prepare-release"] != nil,
            "Release workflow should have prepare-release job",
        )
    }

    @Test("Prepare-release job includes changelog generation")
    func prepareReleaseGeneratesChangelog() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
        )

        #expect(
            workflow.contains("Generate Changelog"),
            "Prepare-release should include changelog generation step",
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

        #expect(jobs["prepare-release"] == nil, "Should not have prepare-release job")
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
            workflow.contains("spk-${{ needs.prepare-release.outputs.version }}-macos-"),
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

    // MARK: - Version File Release

    @Test("Release workflow uses VERSION file as source of truth")
    func releaseUsesVersionFile() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
        )

        #expect(
            workflow.contains("VERSION"),
            "Should read from VERSION file",
        )
        #expect(
            workflow.contains("should_release"),
            "Should have should_release output for conditional release",
        )
    }

    @Test("Release checks if tag already exists")
    func releaseChecksTagExists() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
        )

        #expect(
            workflow.contains("git rev-parse"),
            "Should check if tag exists using git rev-parse",
        )
        #expect(
            workflow.contains("skipping release"),
            "Should skip release when tag exists",
        )
    }

    @Test("Release job has conditional execution based on should_release")
    func releaseJobIsConditional() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
        )

        #expect(
            workflow.contains("should_release == 'true'"),
            "Release job should only run when should_release is true",
        )
    }

    @Test("Release workflow creates tag on push to main")
    func releaseCreatesTagOnPushToMain() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
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
        )

        let parsed = try Yams.load(yaml: workflow) as? [String: Any]
        #expect(parsed != nil, "Full workflow should be valid YAML")

        guard let jobs = parsed?["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["format-check"] != nil, "Should have format-check job")
        #expect(jobs["test"] != nil, "Should have test job")
        #expect(jobs["codeql"] != nil, "Should have codeql job")
        #expect(jobs["prepare-release"] != nil, "Should have prepare-release job")
        #expect(jobs["release"] != nil, "Should have release job")
    }

    // MARK: - Static Analysis

    @Test("Static analysis workflow is valid YAML")
    func staticAnalysisWorkflowIsValidYAML() throws {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeStaticAnalysis: true,
        )
        let parsed = try Yams.load(yaml: workflow)

        #expect(parsed != nil, "Static analysis workflow should be valid YAML")
    }

    @Test("Static analysis includes SWA setup job")
    func staticAnalysisIncludesSetupSWA() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeStaticAnalysis: true,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["setup-swa"] != nil, "Should have setup-swa job")
    }

    @Test("Static analysis includes unused code check")
    func staticAnalysisIncludesUnusedCheck() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeStaticAnalysis: true,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["unused-check"] != nil, "Should have unused-check job")
    }

    @Test("Static analysis includes duplicates check")
    func staticAnalysisIncludesDuplicatesCheck() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeStaticAnalysis: true,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["duplicates-check"] != nil, "Should have duplicates-check job")
    }

    @Test("Static analysis uses artifact sharing for SWA binary")
    func staticAnalysisUsesArtifacts() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeStaticAnalysis: true,
        )

        #expect(workflow.contains("upload-artifact@v4"), "Should upload SWA binary as artifact")
        #expect(workflow.contains("download-artifact@v4"), "Should download SWA binary artifact")
        #expect(workflow.contains("swa-binary"), "Should use swa-binary artifact name")
    }

    @Test("Static analysis has SWA_VERSION environment variable")
    func staticAnalysisHasSWAVersion() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeStaticAnalysis: true,
        )

        guard let env = yaml["env"] as? [String: Any] else {
            Issue.record("env section not found")
            return
        }

        #expect(env["SWA_VERSION"] != nil, "Should have SWA_VERSION env var")
    }

    @Test("Non-static-analysis workflow excludes SWA jobs")
    func nonStaticAnalysisExcludesSWAJobs() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeStaticAnalysis: false,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["setup-swa"] == nil, "Should not have setup-swa job")
        #expect(jobs["unused-check"] == nil, "Should not have unused-check job")
        #expect(jobs["duplicates-check"] == nil, "Should not have duplicates-check job")
    }

    // MARK: - Documentation

    @Test("Docs workflow is valid YAML")
    func docsWorkflowIsValidYAML() throws {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: true,
            docsTarget: "TestPackageCore",
        )
        let parsed = try Yams.load(yaml: workflow)

        #expect(parsed != nil, "Docs workflow should be valid YAML")
    }

    @Test("Docs workflow includes docs job")
    func docsWorkflowIncludesDocsJob() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: true,
            docsTarget: "TestPackageCore",
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["docs"] != nil, "Should have docs job")
    }

    @Test("Docs workflow includes deploy-docs job")
    func docsWorkflowIncludesDeployDocsJob() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: true,
            docsTarget: "TestPackageCore",
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["deploy-docs"] != nil, "Should have deploy-docs job")
    }

    @Test("Docs workflow uses Swift-DocC")
    func docsWorkflowUsesSwiftDocC() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: true,
            docsTarget: "TestPackageCore",
        )

        #expect(workflow.contains("generate-documentation"), "Should use generate-documentation")
        #expect(workflow.contains("--target TestPackageCore"), "Should specify target")
        #expect(workflow.contains("--transform-for-static-hosting"), "Should transform for static hosting")
    }

    @Test("Docs workflow uses custom hosting base path")
    func docsWorkflowUsesCustomHostingBasePath() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: true,
            docsTarget: "TestPackageCore",
            hostingBasePath: "MyCustomPath",
        )

        #expect(
            workflow.contains("--hosting-base-path MyCustomPath"),
            "Should use custom hosting base path",
        )
    }

    @Test("Docs workflow defaults hosting base path to project name")
    func docsWorkflowDefaultsHostingBasePath() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: true,
            docsTarget: "TestPackageCore",
        )

        #expect(
            workflow.contains("--hosting-base-path TestPackage"),
            "Should default hosting base path to project name",
        )
    }

    @Test("Docs workflow uploads pages artifact")
    func docsWorkflowUploadsPages() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: true,
            docsTarget: "TestPackageCore",
        )

        #expect(workflow.contains("upload-pages-artifact@v3"), "Should upload pages artifact")
        #expect(workflow.contains("deploy-pages@v4"), "Should deploy pages")
    }

    @Test("Docs workflow has pages permissions")
    func docsWorkflowHasPagesPermissions() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: true,
            docsTarget: "TestPackageCore",
        )

        guard let permissions = yaml["permissions"] as? [String: Any] else {
            Issue.record("Permissions section not found")
            return
        }

        #expect(permissions["pages"] as? String == "write", "Should have pages: write permission")
        #expect(permissions["id-token"] as? String == "write", "Should have id-token: write permission")
    }

    @Test("Non-docs workflow excludes docs jobs")
    func nonDocsWorkflowExcludesDocsJobs() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: false,
        )

        guard let jobs = yaml["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        #expect(jobs["docs"] == nil, "Should not have docs job")
        #expect(jobs["deploy-docs"] == nil, "Should not have deploy-docs job")
    }

    @Test("Non-docs workflow excludes pages permissions")
    func nonDocsWorkflowExcludesPagesPermissions() throws {
        let yaml = try parseWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeDocs: false,
        )

        guard let permissions = yaml["permissions"] as? [String: Any] else {
            Issue.record("Permissions section not found")
            return
        }

        #expect(permissions["pages"] == nil, "Should not have pages permission")
        #expect(permissions["id-token"] == nil, "Should not have id-token permission")
    }

    // MARK: - Coverage Report

    @Test("Test job generates lcov coverage")
    func testJobGeneratesLcovCoverage() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains("llvm-cov export"), "Should use llvm-cov export for lcov")
        #expect(workflow.contains("-format=lcov"), "Should generate lcov format")
        #expect(workflow.contains("coverage.lcov"), "Should create coverage.lcov file")
    }

    @Test("Test job generates text coverage report")
    func testJobGeneratesTextCoverage() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains("llvm-cov report"), "Should use llvm-cov report for text")
        #expect(workflow.contains("coverage.txt"), "Should create coverage.txt file")
    }

    @Test("Test job uploads coverage artifact")
    func testJobUploadsCoverageArtifact() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains("coverage-report"), "Should upload coverage-report artifact")
        #expect(workflow.contains("retention-days: 30"), "Should retain coverage for 30 days")
    }

    @Test("Coverage excludes test and build directories")
    func coverageExcludesTestAndBuildDirs() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(
            workflow.contains("-ignore-filename-regex='.build|Tests|Fixtures'"),
            "Should ignore build, tests, and fixtures directories",
        )
    }

    // MARK: - Format Check

    @Test("Format check reads paths from .spk.json")
    func formatCheckReadsPathsFromSpkJson() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains(".spk.json"), "Should reference .spk.json")
        #expect(
            workflow.contains("hooks.tasks.format.paths"),
            "Should read format paths from hooks config",
        )
    }

    @Test("Format check has fallback paths")
    func formatCheckHasFallbackPaths() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(
            workflow.contains("Sources/ Tests/ Plugins/"),
            "Should have fallback paths when .spk.json is missing",
        )
    }

    // MARK: - Full Workflow with All Features

    @Test("Full workflow with all features is valid")
    func fullWorkflowWithAllFeaturesIsValid() throws {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
            includeRelease: true,
            includeBinaryRelease: true,
            binaryName: "testpkg",
            includeStaticAnalysis: true,
            includeDocs: true,
            docsTarget: "TestPackageCore",
        )

        let parsed = try Yams.load(yaml: workflow) as? [String: Any]
        #expect(parsed != nil, "Full workflow should be valid YAML")

        guard let jobs = parsed?["jobs"] as? [String: Any] else {
            Issue.record("Jobs section not found")
            return
        }

        // All jobs should be present
        #expect(jobs["setup-swa"] != nil, "Should have setup-swa job")
        #expect(jobs["format-check"] != nil, "Should have format-check job")
        #expect(jobs["unused-check"] != nil, "Should have unused-check job")
        #expect(jobs["duplicates-check"] != nil, "Should have duplicates-check job")
        #expect(jobs["test"] != nil, "Should have test job")
        #expect(jobs["codeql"] != nil, "Should have codeql job")
        #expect(jobs["prepare-release"] != nil, "Should have prepare-release job")
        #expect(jobs["release"] != nil, "Should have release job")
        #expect(jobs["docs"] != nil, "Should have docs job")
        #expect(jobs["deploy-docs"] != nil, "Should have deploy-docs job")
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
        includeStaticAnalysis: Bool = false,
        includeDocs: Bool = false,
        docsTarget: String? = nil,
        hostingBasePath: String? = nil,
    ) throws -> [String: Any] {
        let workflow = DefaultConfigs.ciWorkflow(
            name: name,
            platforms: platforms,
            includeRelease: includeRelease,
            includePlatformMatrix: includePlatformMatrix,
            includeBinaryRelease: includeBinaryRelease,
            binaryName: binaryName,
            includeStaticAnalysis: includeStaticAnalysis,
            includeDocs: includeDocs,
            docsTarget: docsTarget,
            hostingBasePath: hostingBasePath,
        )

        guard let parsed = try Yams.load(yaml: workflow) as? [String: Any] else {
            throw WorkflowParseError.invalidStructure
        }

        return parsed
    }
}

// MARK: - WorkflowParseError

private enum WorkflowParseError: Error {
    case invalidStructure
}

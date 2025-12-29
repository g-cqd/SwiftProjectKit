import Foundation
@testable import SwiftProjectKitCore
import Testing

// MARK: - SwiftLintConfigTests

@Suite("SwiftLint Config Tests")
struct SwiftLintConfigTests {
    @Test("SwiftLint config is not empty")
    func notEmpty() {
        #expect(!DefaultConfigs.swiftlint.isEmpty)
    }

    @Test("SwiftLint config contains expected sections")
    func containsExpectedSections() {
        let config = DefaultConfigs.swiftlint

        #expect(config.contains("disabled_rules:"))
        #expect(config.contains("opt_in_rules:"))
        #expect(config.contains("excluded:"))
        #expect(config.contains("line_length:"))
        #expect(config.contains("file_length:"))
        #expect(config.contains("function_body_length:"))
        #expect(config.contains("type_body_length:"))
        #expect(config.contains("cyclomatic_complexity:"))
        #expect(config.contains("reporter: xcode"))
    }

    @Test("SwiftLint config excludes build directories")
    func excludesBuildDirectories() {
        let config = DefaultConfigs.swiftlint

        #expect(config.contains(".build"))
        #expect(config.contains(".swiftpm"))
        #expect(config.contains("Package.swift"))
        #expect(config.contains("DerivedData"))
    }

    @Test("SwiftLint config has reasonable limits")
    func reasonableLimits() {
        let config = DefaultConfigs.swiftlint

        // Line length
        #expect(config.contains("warning: 120"))
        #expect(config.contains("error: 200"))

        // File length
        #expect(config.contains("warning: 500"))
        #expect(config.contains("error: 1000"))
    }

    @Test("SwiftLint config enables important opt-in rules")
    func importantOptInRules() {
        let config = DefaultConfigs.swiftlint

        #expect(config.contains("force_unwrapping"))
        #expect(config.contains("implicitly_unwrapped_optional"))
        #expect(config.contains("unused_declaration"))
        #expect(config.contains("unused_import"))
        #expect(config.contains("sorted_imports"))
    }
}

// MARK: - SwiftFormatConfigTests

@Suite("SwiftFormat Config Tests")
struct SwiftFormatConfigTests {
    @Test("SwiftFormat config is not empty")
    func testNotEmpty() {
        #expect(!DefaultConfigs.swiftformat.isEmpty)
    }

    @Test("SwiftFormat config contains Swift version")
    func containsSwiftVersion() {
        let config = DefaultConfigs.swiftformat

        #expect(config.contains("--swiftversion"))
    }

    @Test("SwiftFormat config excludes build directories")
    func testExcludesBuildDirectories() {
        let config = DefaultConfigs.swiftformat

        #expect(config.contains("--exclude"))
        #expect(config.contains(".build"))
        #expect(config.contains(".swiftpm"))
        #expect(config.contains("DerivedData"))
    }

    @Test("SwiftFormat config has formatting options")
    func formattingOptions() {
        let config = DefaultConfigs.swiftformat

        #expect(config.contains("--indent"))
        #expect(config.contains("--maxwidth 120"))
        #expect(config.contains("--linebreaks lf"))
        #expect(config.contains("--trimwhitespace always"))
    }

    @Test("SwiftFormat config enables important rules")
    func enabledRules() {
        let config = DefaultConfigs.swiftformat

        #expect(config.contains("--enable blankLineAfterImports"))
        #expect(config.contains("--enable isEmpty"))
        #expect(config.contains("--enable organizeDeclarations"))
    }
}

// MARK: - ClaudeMdTests

@Suite("CLAUDE.md Template Tests")
struct ClaudeMdTests {
    @Test("CLAUDE.md template is not empty")
    func testNotEmpty() {
        #expect(!DefaultConfigs.claudeMd.isEmpty)
    }

    @Test("CLAUDE.md contains core sections")
    func containsCoreSections() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("# Elite Software Engineer Guidelines"))
        #expect(template.contains("## Core Mandates"))
        #expect(template.contains("## Swift Best Practices"))
        #expect(template.contains("## Implementation Guidelines"))
        #expect(template.contains("## Forbidden Patterns"))
    }

    @Test("CLAUDE.md mentions SOLID principles")
    func mentionsSolid() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("SOLID"))
        #expect(template.contains("Single Responsibility"))
        #expect(template.contains("Open/Closed"))
        #expect(template.contains("Liskov Substitution"))
        #expect(template.contains("Interface Segregation"))
        #expect(template.contains("Dependency Inversion"))
    }

    @Test("CLAUDE.md mentions DRY and KISS")
    func mentionsDryKiss() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("DRY"))
        #expect(template.contains("KISS"))
    }

    @Test("CLAUDE.md includes Swift 6 guidelines")
    func swift6Guidelines() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("Swift 6"))
        #expect(template.contains("Strict Concurrency"))
        #expect(template.contains("Sendable"))
        #expect(template.contains("actor"))
    }

    @Test("CLAUDE.md includes forbidden patterns")
    func forbiddenPatterns() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("NEVER"))
        #expect(template.contains("DispatchQueue"))
        #expect(template.contains("try!"))
        #expect(template.contains("force unwrap"))
    }
}

// MARK: - CIWorkflowTests

@Suite("CI Workflow Tests")
struct CIWorkflowTests {
    @Test("CI workflow for single platform has no matrix")
    func singlePlatformNoMatrix() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains("name: CI"))
        #expect(workflow.contains("lint:"))
        #expect(workflow.contains("build-and-test:"))
        #expect(!workflow.contains("build-platforms:"))
        #expect(!workflow.contains("strategy:"))
        #expect(!workflow.contains("matrix:"))
    }

    @Test("CI workflow for multiple platforms has matrix")
    func multiplePlatformsHasMatrix() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .allPlatforms,
        )

        #expect(workflow.contains("build-platforms:"))
        #expect(workflow.contains("strategy:"))
        #expect(workflow.contains("matrix:"))
        #expect(workflow.contains("platform: iOS"))
        #expect(workflow.contains("platform: macOS"))
    }

    @Test("CI workflow contains correct triggers")
    func correctTriggers() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains("on:"))
        #expect(workflow.contains("push:"))
        #expect(workflow.contains("pull_request:"))
        #expect(workflow.contains("branches: [main]"))
    }

    @Test("CI workflow uses correct Xcode selection")
    func xcodeSelection() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains("xcode-select"))
        #expect(workflow.contains("Xcode"))
    }

    @Test("CI workflow includes lint job")
    func lintJob() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains("lint:"))
        #expect(workflow.contains("SwiftLint"))
        #expect(workflow.contains("SwiftFormat"))
        #expect(workflow.contains("swiftlint lint"))
        #expect(workflow.contains("swiftformat --lint"))
    }

    @Test("CI workflow includes build and test")
    func buildAndTest() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains("swift build"))
        #expect(workflow.contains("swift test"))
    }

    @Test("CI workflow uses concurrency control")
    func concurrencyControl() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "TestPackage",
            platforms: .macOSOnly,
        )

        #expect(workflow.contains("concurrency:"))
        // Cancel-in-progress is conditional: only cancels for PRs
        #expect(workflow.contains("cancel-in-progress: ${{ github.event_name == 'pull_request' }}"))
    }

    @Test("CI workflow platform matrix respects configuration")
    func platformMatrixRespectsConfig() {
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
        )

        #expect(workflow.contains("platform: iOS"))
        #expect(workflow.contains("platform: macOS"))
        #expect(!workflow.contains("platform: tvOS"))
        #expect(!workflow.contains("platform: watchOS"))
        #expect(!workflow.contains("platform: visionOS"))
    }

    @Test("CI workflow uses package name in xcodebuild scheme")
    func packageNameInScheme() {
        let workflow = DefaultConfigs.ciWorkflow(
            name: "MyAwesomePackage",
            platforms: .allPlatforms,
        )

        #expect(workflow.contains("-scheme MyAwesomePackage"))
    }
}

// MARK: - ReleaseWorkflowTests

@Suite("Release Workflow Tests")
struct ReleaseWorkflowTests {
    @Test("Release workflow is not empty")
    func testNotEmpty() {
        let workflow = DefaultConfigs.releaseWorkflow(name: "TestPackage")
        #expect(!workflow.isEmpty)
    }

    @Test("Release workflow contains correct triggers")
    func testCorrectTriggers() {
        let workflow = DefaultConfigs.releaseWorkflow(name: "TestPackage")

        #expect(workflow.contains("on:"))
        #expect(workflow.contains("push:"))
        #expect(workflow.contains("tags:"))
        #expect(workflow.contains("'v*'"))
        #expect(workflow.contains("workflow_dispatch:"))
    }

    @Test("Release workflow has validate job")
    func validateJob() {
        let workflow = DefaultConfigs.releaseWorkflow(name: "TestPackage")

        #expect(workflow.contains("validate:"))
        #expect(workflow.contains("swift build"))
        #expect(workflow.contains("swift test"))
    }

    @Test("Release workflow generates changelog")
    func changelogGeneration() {
        let workflow = DefaultConfigs.releaseWorkflow(name: "TestPackage")

        #expect(workflow.contains("changelog:"))
        #expect(workflow.contains("Generate Changelog"))
        #expect(workflow.contains("git log"))
    }

    @Test("Release workflow creates GitHub release")
    func createsGitHubRelease() {
        let workflow = DefaultConfigs.releaseWorkflow(name: "TestPackage")

        #expect(workflow.contains("create-release:"))
        #expect(workflow.contains("softprops/action-gh-release"))
        #expect(workflow.contains("GITHUB_TOKEN"))
    }

    @Test("Release workflow uses package name correctly")
    func packageNameUsage() {
        let workflow = DefaultConfigs.releaseWorkflow(name: "MyLibrary")

        #expect(workflow.contains("MyLibrary"))
        #expect(workflow.contains("g-cqd/MyLibrary"))
    }

    @Test("Release workflow has write permissions")
    func writePermissions() {
        let workflow = DefaultConfigs.releaseWorkflow(name: "TestPackage")

        #expect(workflow.contains("permissions:"))
        #expect(workflow.contains("contents: write"))
    }

    @Test("Release workflow supports prerelease detection")
    func prereleaseDetection() {
        let workflow = DefaultConfigs.releaseWorkflow(name: "TestPackage")

        #expect(workflow.contains("prerelease:"))
        #expect(workflow.contains("alpha"))
        #expect(workflow.contains("beta"))
        #expect(workflow.contains("rc"))
    }

    @Test("Release workflow includes installation instructions")
    func installationInstructions() {
        let workflow = DefaultConfigs.releaseWorkflow(name: "TestPackage")

        #expect(workflow.contains("## Installation"))
        #expect(workflow.contains("Swift Package Manager"))
        #expect(workflow.contains(".package"))
    }
}

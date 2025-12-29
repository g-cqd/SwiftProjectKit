@testable import SwiftProjectKitCore
import Testing

@Test func versionExists() {
    #expect(!swiftProjectKitVersion.isEmpty)
}

@Test func testDefaultSwiftVersion() {
    #expect(defaultSwiftVersion == "6.2")
}

@Test func managedTools() {
    #expect(ManagedTool.swiftlint.repository == "realm/SwiftLint")
    #expect(ManagedTool.swiftformat.repository == "nicklockwood/SwiftFormat")
}

@Test func platformConfiguration() {
    let allPlatforms = PlatformConfiguration.allPlatforms
    #expect(allPlatforms.enabledPlatforms.count == 5)

    let macOSOnly = PlatformConfiguration.macOSOnly
    #expect(macOSOnly.enabledPlatforms == ["macOS"])
}

@Test func projectConfiguration() {
    let config = ProjectConfiguration.default
    #expect(config.swiftVersion == "6.2")
    #expect(config.swiftlint.enabled)
    #expect(config.swiftformat.enabled)
}

@Test func defaultConfigs() {
    #expect(DefaultConfigs.swiftlint.contains("disabled_rules"))
    #expect(DefaultConfigs.swiftformat.contains("--swiftversion"))
    #expect(DefaultConfigs.claudeMd.contains("Elite Software Engineer"))
}

@Test func cIWorkflowGeneration() {
    let workflow = DefaultConfigs.ciWorkflow(name: "TestPackage", platforms: .macOSOnly)
    #expect(workflow.contains("name: CI"))
    #expect(workflow.contains("swift build"))
    #expect(!workflow.contains("build-platforms")) // No platform matrix for macOS-only

    // Platform matrix is opt-in (for library packages targeting multiple platforms)
    let multiPlatformWorkflow = DefaultConfigs.ciWorkflow(
        name: "TestPackage",
        platforms: .allPlatforms,
        includePlatformMatrix: true
    )
    #expect(multiPlatformWorkflow.contains("build-platforms"))
    #expect(multiPlatformWorkflow.contains("iOS"))
}

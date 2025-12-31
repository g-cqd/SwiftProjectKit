//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import ArgumentParser
import Foundation
import SwiftProjectKitCore

// MARK: - BuildCommand

struct BuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build your Swift project with all quality checks",
        discussion: """
            Runs a comprehensive build pipeline:
              1. Clean (optional)
              2. Resolve/update package dependencies
              3. Format code with swift-format
              4. Check and sync version files
              5. Lint code
              6. Build the project
              7. Run tests (optional)

            Automatically detects project type (SPM or Xcode) and uses
            the appropriate toolchain commands.
            """
    )

    // MARK: - Options

    @Flag(name: .long, help: "Clean build artifacts before building")
    var clean = false

    @Flag(name: .long, help: "Update package dependencies (not just resolve)")
    var update = false

    @Flag(name: .long, help: "Skip formatting step")
    var skipFormat = false

    @Flag(name: .long, help: "Skip version sync step")
    var skipVersionSync = false

    @Flag(name: .long, help: "Skip linting step")
    var skipLint = false

    @Flag(name: .long, help: "Skip test step")
    var skipTests = false

    @Flag(name: .long, help: "Run tests after build")
    var test = false

    @Option(name: .long, help: "Build configuration (debug, release)")
    var configuration: String = "debug"

    @Option(name: .long, help: "Specific scheme to build (Xcode projects, auto-detected if not specified)")
    var scheme: String?

    @Option(name: .long, help: "Specific target to build (Xcode projects)")
    var target: String?

    @Option(name: .long, help: "Platform to build for (iOS, macOS, watchOS, tvOS, visionOS)")
    var platform: String?

    @Option(name: .long, help: "Device type filter (iphone, ipad, appletv, applevisionpro, applewatch)")
    var deviceType: String?

    @Option(name: .long, help: "Destination specifier for xcodebuild (overrides platform/deviceType)")
    var destination: String?

    @Flag(name: .long, help: "Run steps in parallel where possible")
    var parallel = false

    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose = false

    @Flag(name: .long, inversion: .prefixedNo, help: "Fix issues automatically where possible")
    var fix = true

    @Flag(name: .long, help: "Dry run - show what would be done without executing")
    var dryRun = false

    // MARK: - Run

    func run() async throws {
        let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let projectType = detectProjectType(at: projectRoot)
        let runner = BuildRunner(
            projectRoot: projectRoot,
            projectType: projectType,
            options: buildOptions(),
            verbose: verbose,
            dryRun: dryRun
        )

        print("🔨 Building \(projectType.description) project...")
        if verbose {
            print("   Root: \(projectRoot.path)")
            print("   Configuration: \(configuration)")
        }
        print("")

        let result = try await runner.run()

        guard result.success else {
            print("\n❌ Build failed")
            printSummary(result)
            throw ExitCode.failure
        }
        print("\n✅ Build completed successfully!")
        printSummary(result)
    }

    // MARK: - Private

    private func detectProjectType(at root: URL) -> ProjectType {
        let fm = FileManager.default

        // Check for Xcode project/workspace
        let contents = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []

        if contents.contains(where: { $0.hasSuffix(".xcworkspace") }) {
            return .xcodeWorkspace
        }
        if contents.contains(where: { $0.hasSuffix(".xcodeproj") }) {
            return .xcodeProject
        }
        if fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
            return .swiftPackage
        }

        return .swiftPackage  // Default to SPM
    }

    private func buildOptions() -> BuildOptions {
        BuildOptions(
            clean: clean,
            update: update,
            skipFormat: skipFormat,
            skipVersionSync: skipVersionSync,
            skipLint: skipLint,
            skipTests: skipTests || !test,
            configuration: configuration,
            scheme: scheme,
            target: target,
            platform: platform,
            deviceType: deviceType,
            destination: destination,
            parallel: parallel,
            fix: fix
        )
    }

    private func printSummary(_ result: BuildResult) {
        if verbose || !result.success {
            print("\nStep Summary:")
            for step in result.steps {
                let icon = step.success ? "✓" : "✗"
                let duration = step.duration.map { String(format: " (%.2fs)", $0) } ?? ""
                print("  \(icon) \(step.name)\(duration)")

                if !step.success, let error = step.error {
                    print("    Error: \(error)")
                }
            }
        }

        if let totalDuration = result.totalDuration {
            print(String(format: "\nTotal time: %.2fs", totalDuration))
        }
    }
}

// MARK: - ProjectType

enum ProjectType: CustomStringConvertible {
    case swiftPackage
    case xcodeProject
    case xcodeWorkspace

    var description: String {
        switch self {
        case .swiftPackage: "Swift Package"
        case .xcodeProject: "Xcode Project"
        case .xcodeWorkspace: "Xcode Workspace"
        }
    }
}

// MARK: - BuildOptions

struct BuildOptions {
    var clean: Bool
    var update: Bool
    var skipFormat: Bool
    var skipVersionSync: Bool
    var skipLint: Bool
    var skipTests: Bool
    var configuration: String
    var scheme: String?
    var target: String?
    var platform: String?
    var deviceType: String?
    var destination: String?
    var parallel: Bool
    var fix: Bool
}

// MARK: - BuildResult

struct BuildResult {
    var success: Bool
    var steps: [StepResult]
    var totalDuration: Double?
}

struct StepResult {
    var name: String
    var success: Bool
    var duration: Double?
    var error: String?
}

// MARK: - BuildRunner

actor BuildRunner {
    private let projectRoot: URL
    private let projectType: ProjectType
    private let options: BuildOptions
    private let verbose: Bool
    private let dryRun: Bool

    init(
        projectRoot: URL,
        projectType: ProjectType,
        options: BuildOptions,
        verbose: Bool,
        dryRun: Bool
    ) {
        self.projectRoot = projectRoot
        self.projectType = projectType
        self.options = options
        self.verbose = verbose
        self.dryRun = dryRun
    }

    func run() async throws -> BuildResult {
        let startTime = ContinuousClock.now
        var steps: [StepResult] = []
        var success = true

        // Step 1: Clean
        if options.clean {
            let result = await runStep("Clean") { try await self.clean() }
            steps.append(result)
            if !result.success { success = false }
        }

        // Step 2: Resolve/Update dependencies
        let resolveResult = await runStep(options.update ? "Update Dependencies" : "Resolve Dependencies") {
            try await self.resolveDependencies()
        }
        steps.append(resolveResult)
        if !resolveResult.success {
            success = false
        }

        guard success else {
            return BuildResult(success: false, steps: steps, totalDuration: elapsed(from: startTime))
        }

        // Step 3: Format
        if !options.skipFormat {
            let result = await runStep("Format") { try await self.format() }
            steps.append(result)
            if !result.success { success = false }
        }

        // Step 4: Version Sync
        if !options.skipVersionSync {
            let result = await runStep("Version Sync") { try await self.versionSync() }
            steps.append(result)
            if !result.success { success = false }
        }

        // Step 5: Lint
        if !options.skipLint {
            let result = await runStep("Lint") { try await self.lint() }
            steps.append(result)
            if !result.success { success = false }
        }

        guard success else {
            return BuildResult(success: false, steps: steps, totalDuration: elapsed(from: startTime))
        }

        // Step 6: Build
        let buildResult = await runStep("Build") { try await self.build() }
        steps.append(buildResult)
        if !buildResult.success {
            success = false
        }

        guard success else {
            return BuildResult(success: false, steps: steps, totalDuration: elapsed(from: startTime))
        }

        // Step 7: Test
        if !options.skipTests {
            let testResult = await runStep("Test") { try await self.test() }
            steps.append(testResult)
            if !testResult.success {
                success = false
            }
        }

        return BuildResult(
            success: success,
            steps: steps,
            totalDuration: elapsed(from: startTime)
        )
    }

    // MARK: - Steps

    private func clean() async throws {
        printStep("Cleaning build artifacts...")

        if dryRun {
            print("  [dry-run] Would clean build artifacts")
            return
        }

        switch projectType {
        case .swiftPackage:
            _ = try await Shell.run("swift", arguments: ["package", "clean"], in: projectRoot)

        case .xcodeProject, .xcodeWorkspace:
            var args = ["clean"]
            if let scheme = options.scheme {
                args += ["-scheme", scheme]
            }
            args += ["-configuration", options.configuration.capitalized]
            _ = try await Shell.run("xcodebuild", arguments: args, in: projectRoot)
        }
    }

    private func resolveDependencies() async throws {
        let action = options.update ? "Updating" : "Resolving"
        printStep("\(action) dependencies...")

        if dryRun {
            print("  [dry-run] Would \(action.lowercased()) dependencies")
            return
        }

        switch projectType {
        case .swiftPackage:
            if options.update {
                _ = try await Shell.run(
                    "swift",
                    arguments: ["package", "update"],
                    in: projectRoot
                )
            } else {
                _ = try await Shell.run(
                    "swift",
                    arguments: ["package", "resolve"],
                    in: projectRoot
                )
            }

        case .xcodeProject, .xcodeWorkspace:
            // xcodebuild resolves automatically, but we can force it
            var args = ["-resolvePackageDependencies"]
            if projectType == .xcodeWorkspace {
                if let workspace = findWorkspace() {
                    args += ["-workspace", workspace]
                }
            }
            _ = try await Shell.run("xcodebuild", arguments: args, in: projectRoot)
        }
    }

    private func format() async throws {
        printStep("Formatting code...")

        if dryRun {
            print("  [dry-run] Would format code")
            return
        }

        let configPath = projectRoot.appendingPathComponent(".swift-format")
        var args = ["format", "--in-place", "--parallel", "--recursive"]

        if FileManager.default.fileExists(atPath: configPath.path) {
            args += ["--configuration", configPath.path]
        }

        args += ["Sources/", "Tests/"]

        // Use swift-format from Xcode toolchain
        let swiftFormat =
            "/Applications/Xcode-beta.app/Contents/Developer/Toolchains/"
            + "XcodeDefault.xctoolchain/usr/bin/swift-format"

        if FileManager.default.fileExists(atPath: swiftFormat) {
            _ = try await Shell.run(swiftFormat, arguments: args, in: projectRoot)
        } else {
            // Fallback to PATH
            _ = try await Shell.run("swift-format", arguments: args, in: projectRoot)
        }
    }

    private func versionSync() async throws {
        printStep("Checking version sync...")

        if dryRun {
            print("  [dry-run] Would check version sync")
            return
        }

        let versionFile = projectRoot.appendingPathComponent("VERSION")
        guard FileManager.default.fileExists(atPath: versionFile.path) else {
            if verbose {
                print("  No VERSION file found, skipping version sync")
            }
            return
        }

        let version = try String(contentsOf: versionFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if verbose {
            print("  Current version: \(version)")
        }

        // For now, just verify the VERSION file is readable
        // Full version sync would check other files match
    }

    private func lint() async throws {
        printStep("Linting code...")

        if dryRun {
            print("  [dry-run] Would lint code")
            return
        }

        let configPath = projectRoot.appendingPathComponent(".swift-format")
        var args = ["lint", "--parallel", "--recursive"]

        if FileManager.default.fileExists(atPath: configPath.path) {
            args += ["--configuration", configPath.path]
        }

        args += ["Sources/", "Tests/"]

        let swiftFormat =
            "/Applications/Xcode-beta.app/Contents/Developer/Toolchains/"
            + "XcodeDefault.xctoolchain/usr/bin/swift-format"

        if FileManager.default.fileExists(atPath: swiftFormat) {
            _ = try await Shell.run(swiftFormat, arguments: args, in: projectRoot)
        } else {
            _ = try await Shell.run("swift-format", arguments: args, in: projectRoot)
        }
    }

    private func build() async throws {
        printStep("Building project...")

        if dryRun {
            print("  [dry-run] Would build project")
            return
        }

        switch projectType {
        case .swiftPackage:
            var args = ["build"]
            if options.configuration.lowercased() == "release" {
                args += ["-c", "release"]
            }
            _ = try await Shell.run("swift", arguments: args, in: projectRoot)

        case .xcodeProject, .xcodeWorkspace:
            var args = ["build"]

            // Add workspace if applicable
            if projectType == .xcodeWorkspace {
                if let workspace = findWorkspace() {
                    args += ["-workspace", workspace]
                }
            } else if let project = findXcodeProject() {
                args += ["-project", project]
            }

            // Resolve scheme (auto-detect if not specified)
            if let scheme = try await resolveScheme() {
                args += ["-scheme", scheme]
            } else if let target = options.target {
                args += ["-target", target]
            }

            args += ["-configuration", options.configuration.capitalized]

            // Handle destination
            if let destination = options.destination {
                args += ["-destination", destination]
            } else if let platform = options.platform {
                args += ["-destination", await destinationForPlatform(platform)]
            }

            if verbose {
                print("  xcodebuild \(args.joined(separator: " "))")
            }

            _ = try await Shell.run("xcodebuild", arguments: args, in: projectRoot)
        }
    }

    private func test() async throws {
        printStep("Running tests...")

        if dryRun {
            print("  [dry-run] Would run tests")
            return
        }

        switch projectType {
        case .swiftPackage:
            var args = ["test", "--parallel"]
            if options.configuration.lowercased() == "release" {
                args += ["-c", "release"]
            }
            _ = try await Shell.run("swift", arguments: args, in: projectRoot)

        case .xcodeProject, .xcodeWorkspace:
            var args = ["test"]

            // Add workspace/project
            if projectType == .xcodeWorkspace {
                if let workspace = findWorkspace() {
                    args += ["-workspace", workspace]
                }
            } else if let project = findXcodeProject() {
                args += ["-project", project]
            }

            // Resolve scheme (auto-detect if not specified)
            if let scheme = try await resolveScheme() {
                args += ["-scheme", scheme]
            }

            args += ["-configuration", options.configuration.capitalized]

            // Handle destination
            if let destination = options.destination {
                args += ["-destination", destination]
            } else if let platform = options.platform {
                args += ["-destination", await destinationForPlatform(platform)]
            } else {
                // Default to Mac for testing
                args += ["-destination", "platform=macOS"]
            }

            if verbose {
                print("  xcodebuild \(args.joined(separator: " "))")
            }

            _ = try await Shell.run("xcodebuild", arguments: args, in: projectRoot)
        }
    }

    /// Convert platform name to xcodebuild destination specifier
    /// Dynamically detects available simulators and picks the most recent one
    private func destinationForPlatform(_ platform: String) async -> String {
        let deviceTypeFilter = options.deviceType

        switch platform.lowercased() {
        case "ios":
            if let device = await detectBestDevice(for: "iOS", deviceType: deviceTypeFilter) {
                return "platform=iOS Simulator,id=\(device.udid)"
            }
            return "platform=iOS Simulator,name=iPhone 16"

        case "macos", "mac":
            return "platform=macOS"

        case "watchos":
            if let device = await detectBestDevice(for: "watchOS", deviceType: deviceTypeFilter) {
                return "platform=watchOS Simulator,id=\(device.udid)"
            }
            return "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)"

        case "tvos":
            if let device = await detectBestDevice(for: "tvOS", deviceType: deviceTypeFilter) {
                return "platform=tvOS Simulator,id=\(device.udid)"
            }
            return "platform=tvOS Simulator,name=Apple TV 4K (3rd generation)"

        case "visionos":
            if let device = await detectBestDevice(for: "visionOS", deviceType: deviceTypeFilter) {
                return "platform=visionOS Simulator,id=\(device.udid)"
            }
            return "platform=visionOS Simulator,name=Apple Vision Pro"

        default:
            // Assume it's already a valid destination specifier
            return "platform=\(platform)"
        }
    }

    /// Simulator device info
    private struct SimulatorDevice {
        let name: String
        let udid: String
        let runtime: String
        let isAvailable: Bool
    }

    /// Detect available simulator devices for a platform
    private func detectAvailableDevices(for platform: String) async -> [SimulatorDevice] {
        do {
            let output = try await Shell.run(
                "xcrun",
                arguments: ["simctl", "list", "devices", "available", "-j"],
                in: projectRoot
            )

            guard let data = output.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let devices = json["devices"] as? [String: [[String: Any]]]
            else {
                return []
            }

            var result: [SimulatorDevice] = []

            for (runtime, deviceList) in devices {
                // Filter by platform (e.g., "com.apple.CoreSimulator.SimRuntime.iOS-18-0")
                guard runtime.lowercased().contains(platform.lowercased()) else { continue }

                for device in deviceList {
                    guard let name = device["name"] as? String,
                        let udid = device["udid"] as? String,
                        let isAvailable = device["isAvailable"] as? Bool,
                        isAvailable
                    else { continue }

                    result.append(
                        SimulatorDevice(
                            name: name,
                            udid: udid,
                            runtime: runtime,
                            isAvailable: isAvailable
                        )
                    )
                }
            }

            return result
        } catch {
            return []
        }
    }

    /// Detect the best (most recent) device for a platform
    private func detectBestDevice(
        for platform: String,
        deviceType: String? = nil
    ) async -> SimulatorDevice? {
        var devices = await detectAvailableDevices(for: platform)

        guard !devices.isEmpty else { return nil }

        // Filter by device type if specified
        if let deviceType = deviceType?.lowercased() {
            devices = devices.filter { device in
                let name = device.name.lowercased()
                switch deviceType {
                case "iphone":
                    return name.hasPrefix("iphone")
                case "ipad":
                    return name.hasPrefix("ipad")
                case "appletv", "apple tv":
                    return name.contains("apple tv")
                case "applewatch", "apple watch":
                    return name.contains("apple watch")
                case "applevisionpro", "apple vision pro", "vision":
                    return name.contains("apple vision")
                default:
                    // Try direct prefix/contains match
                    return name.hasPrefix(deviceType) || name.contains(deviceType)
                }
            }
        }

        guard !devices.isEmpty else {
            if verbose {
                print("  No devices matching filter '\(deviceType ?? "none")'")
            }
            return nil
        }

        // Sort by runtime version (descending) to get the most recent
        // Runtime format: com.apple.CoreSimulator.SimRuntime.iOS-18-0
        let sorted = devices.sorted { lhs, rhs in
            lhs.runtime > rhs.runtime
        }

        // For iOS, prefer iPhone over iPad, and newer models (unless filtered)
        if platform.lowercased() == "ios" && deviceType == nil {
            // Prefer iPhones with higher numbers (e.g., iPhone 16 over iPhone 15)
            let iphones = sorted.filter { $0.name.hasPrefix("iPhone") }
            if let best = selectBestIPhone(from: iphones) {
                return best
            }
        } else if deviceType?.lowercased() == "iphone" {
            if let best = selectBestIPhone(from: sorted) {
                return best
            }
        } else if deviceType?.lowercased() == "ipad" {
            if let best = selectBestIPad(from: sorted) {
                return best
            }
        }

        if verbose, let first = sorted.first {
            print("  Selected simulator: \(first.name) (\(first.runtime))")
        }

        return sorted.first
    }

    /// Select the best iPad from a list
    private func selectBestIPad(from devices: [SimulatorDevice]) -> SimulatorDevice? {
        // Prefer Pro > Air > regular, and larger sizes
        let ranked = devices.sorted { lhs, rhs in
            let lhsScore = ipadScore(lhs.name)
            let rhsScore = ipadScore(rhs.name)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.name > rhs.name
        }

        if verbose, let first = ranked.first {
            print("  Selected iPad: \(first.name)")
        }

        return ranked.first
    }

    /// Score an iPad name for ranking
    private func ipadScore(_ name: String) -> Int {
        var score = 0

        // Prefer Pro models
        if name.contains("Pro") {
            score += 100
        } else if name.contains("Air") {
            score += 50
        }

        // Prefer larger sizes
        if name.contains("13") || name.contains("12.9") {
            score += 30
        } else if name.contains("11") {
            score += 20
        }

        return score
    }

    /// Select the best iPhone from a list (prefer higher model numbers)
    private func selectBestIPhone(from devices: [SimulatorDevice]) -> SimulatorDevice? {
        // Sort by model number, preferring Pro Max > Pro > Plus > regular
        let ranked = devices.sorted { lhs, rhs in
            let lhsScore = iphoneScore(lhs.name)
            let rhsScore = iphoneScore(rhs.name)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            // If same score, prefer by name (alphabetically descending for newer models)
            return lhs.name > rhs.name
        }

        if verbose, let first = ranked.first {
            print("  Selected iPhone: \(first.name)")
        }

        return ranked.first
    }

    /// Score an iPhone name for ranking (higher is better)
    private func iphoneScore(_ name: String) -> Int {
        var score = 0

        // Extract model number
        if let range = name.range(of: "\\d+", options: .regularExpression) {
            let number = Int(name[range]) ?? 0
            score += number * 100  // Base score from model number
        }

        // Bonus for variant
        if name.contains("Pro Max") {
            score += 30
        } else if name.contains("Pro") {
            score += 20
        } else if name.contains("Plus") {
            score += 10
        }

        return score
    }

    // MARK: - Helpers

    private func runStep(_ name: String, action: () async throws -> Void) async -> StepResult {
        let start = ContinuousClock.now
        do {
            try await action()
            return StepResult(
                name: name,
                success: true,
                duration: elapsed(from: start)
            )
        } catch {
            return StepResult(
                name: name,
                success: false,
                duration: elapsed(from: start),
                error: error.localizedDescription
            )
        }
    }

    private func printStep(_ message: String) {
        print("▸ \(message)")
    }

    private func elapsed(from start: ContinuousClock.Instant) -> Double {
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }

    private func findWorkspace() -> String? {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: projectRoot.path)) ?? []
        return contents.first { $0.hasSuffix(".xcworkspace") }
    }

    private func findXcodeProject() -> String? {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: projectRoot.path)) ?? []
        return contents.first { $0.hasSuffix(".xcodeproj") }
    }

    /// Auto-detect schemes from Xcode project/workspace
    private func detectSchemes() async throws -> [String] {
        var args = ["-list", "-json"]

        if let workspace = findWorkspace() {
            args += ["-workspace", workspace]
        } else if let project = findXcodeProject() {
            args += ["-project", project]
        }

        let output = try await Shell.run("xcodebuild", arguments: args, in: projectRoot)

        // Parse JSON output to extract schemes
        guard let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let project = json["project"] as? [String: Any] ?? json["workspace"] as? [String: Any],
            let schemes = project["schemes"] as? [String]
        else {
            return []
        }

        return schemes
    }

    /// Auto-detect targets from Xcode project
    private func detectTargets() async throws -> [String] {
        var args = ["-list", "-json"]

        if let workspace = findWorkspace() {
            args += ["-workspace", workspace]
        } else if let project = findXcodeProject() {
            args += ["-project", project]
        }

        let output = try await Shell.run("xcodebuild", arguments: args, in: projectRoot)

        guard let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let project = json["project"] as? [String: Any],
            let targets = project["targets"] as? [String]
        else {
            return []
        }

        return targets
    }

    /// Select the most appropriate scheme based on heuristics
    private func selectBestScheme(from schemes: [String]) -> String? {
        guard !schemes.isEmpty else { return nil }

        // Priority order:
        // 1. Scheme matching the project/workspace name
        // 2. Scheme without "Tests" or "UITests" suffix
        // 3. First scheme

        let projectName =
            findWorkspace()?.replacingOccurrences(of: ".xcworkspace", with: "")
            ?? findXcodeProject()?.replacingOccurrences(of: ".xcodeproj", with: "")
            ?? ""

        // Try exact match with project name
        if let match = schemes.first(where: { $0 == projectName }) {
            return match
        }

        // Filter out test schemes
        let nonTestSchemes = schemes.filter {
            !$0.hasSuffix("Tests") && !$0.hasSuffix("UITests")
        }

        if let first = nonTestSchemes.first {
            return first
        }

        return schemes.first
    }

    /// Resolve the scheme to use for build operations
    private func resolveScheme() async throws -> String? {
        // Use explicitly provided scheme
        if let scheme = options.scheme {
            return scheme
        }

        // For SPM, no scheme needed
        guard projectType != .swiftPackage else { return nil }

        // Auto-detect schemes
        let schemes = try await detectSchemes()

        guard !schemes.isEmpty else {
            if verbose {
                print("  No schemes found in project")
            }
            return nil
        }

        if verbose {
            print("  Available schemes: \(schemes.joined(separator: ", "))")
        }

        let selected = selectBestScheme(from: schemes)
        if verbose, let selected {
            print("  Selected scheme: \(selected)")
        }

        return selected
    }
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation

// MARK: - VersionSource

/// Source for the canonical version number
public enum VersionSource: Sendable, Equatable {
    /// Read version from .spk.json's project.version field (default)
    case spk
    /// Read version from a file (e.g., VERSION)
    case file(String)

    /// Default source is .spk (reads from .spk.json)
    public static let `default`: VersionSource = .spk
}

// MARK: - VersionSyncTask

/// Task that ensures version numbers are consistent across files.
///
/// Reads the version from a configurable source and ensures
/// all configured target files have matching versions.
public struct VersionSyncTask: HookTask {
    public let id = "versionSync"
    public let name = "Version Sync"
    public let hooks: Set<HookType> = [.preCommit, .ci]
    public let supportsFix = true
    public let fixSafety: FixSafety = .safe
    public let isBlocking = true

    public var filePatterns: [String] {
        var patterns = syncTargets.map(\.file)
        if case .file(let path) = source {
            patterns.insert(path, at: 0)
        }
        return patterns
    }

    private let source: VersionSource
    private let syncTargets: [SyncTarget]

    /// Initialize with a version source and sync targets
    /// - Parameters:
    ///   - source: Where to read the version from (default: .spk)
    ///   - syncTargets: Files to sync the version to
    public init(
        source: VersionSource = .spk,
        syncTargets: [SyncTarget] = []
    ) {
        self.source = source
        self.syncTargets = syncTargets
    }

    /// Legacy initializer for backwards compatibility with sourceFile parameter
    public init(
        sourceFile: String,
        syncTargets: [SyncTarget] = []
    ) {
        self.source = .file(sourceFile)
        self.syncTargets = syncTargets
    }

    public struct SyncTarget: Sendable {
        public let file: String
        public let pattern: String

        public init(file: String, pattern: String) {
            self.file = file
            self.pattern = pattern
        }
    }

    public func run(context: HookContext) async throws -> TaskResult {
        let startTime = ContinuousClock.now

        // Read source version
        let version: String
        do {
            version = try readSourceVersion(context: context)
        } catch VersionSyncError.sourceNotFound(let description) {
            return .skipped(reason: description)
        } catch VersionSyncError.emptyVersion(let source) {
            return .failed(diagnostics: [
                HookDiagnostic(
                    file: source,
                    message: "Version is empty",
                    severity: .error
                )
            ])
        }

        // Check each target
        var diagnostics: [HookDiagnostic] = []
        var filesChecked = 0

        for target in syncTargets {
            filesChecked += 1
            let result = try checkTarget(target, expectedVersion: version, context: context)
            if let diagnostic = result {
                diagnostics.append(diagnostic)
            }
        }

        let duration = ContinuousClock.now - startTime

        if diagnostics.isEmpty {
            return .passed(duration: duration, filesChecked: filesChecked)
        }

        return .failed(
            diagnostics: diagnostics,
            duration: duration,
            filesChecked: filesChecked,
            fixesAvailable: true
        )
    }

    public func fix(context: HookContext) async throws -> FixResult {
        // Read source version
        let version: String
        do {
            version = try readSourceVersion(context: context)
        } catch {
            return FixResult()
        }

        var filesModified: [String] = []
        var fixesApplied = 0

        for target in syncTargets {
            let fixed = try fixTarget(target, version: version, context: context)
            if fixed {
                filesModified.append(target.file)
                fixesApplied += 1
            }
        }

        return FixResult(
            filesModified: filesModified,
            fixesApplied: fixesApplied
        )
    }

    // MARK: - Version Reading

    private func readSourceVersion(context: HookContext) throws -> String {
        switch source {
        case .spk:
            return try readVersionFromSPK(context: context)
        case .file(let path):
            return try readVersionFromFile(path: path, context: context)
        }
    }

    private func readVersionFromSPK(context: HookContext) throws -> String {
        let configPath = context.projectRoot.appendingPathComponent(".spk.json")

        guard FileManager.default.fileExists(atPath: configPath.path) else {
            throw VersionSyncError.sourceNotFound("No .spk.json file found")
        }

        let data = try Data(contentsOf: configPath)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let projectJson = json?["project"] as? [String: Any],
            let version = projectJson["version"] as? String
        else {
            throw VersionSyncError.sourceNotFound("No project.version in .spk.json")
        }

        guard !version.isEmpty else {
            throw VersionSyncError.emptyVersion(".spk.json")
        }

        return version
    }

    private func readVersionFromFile(path: String, context: HookContext) throws -> String {
        let sourceURL = context.projectRoot.appendingPathComponent(path)

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw VersionSyncError.sourceNotFound("No \(path) file found")
        }

        let version = try String(contentsOf: sourceURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !version.isEmpty else {
            throw VersionSyncError.emptyVersion(path)
        }

        return version
    }

    // MARK: - Private

    private func checkTarget(
        _ target: SyncTarget,
        expectedVersion: String,
        context: HookContext
    ) throws -> HookDiagnostic? {
        let targetURL = context.projectRoot.appendingPathComponent(target.file)

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return HookDiagnostic(
                file: target.file,
                message: "File not found",
                severity: .error
            )
        }

        let content = try String(contentsOf: targetURL, encoding: .utf8)

        // Create regex from pattern (pattern should have a capture group for version)
        guard let regex = try? Regex(target.pattern) else {
            return HookDiagnostic(
                file: target.file,
                message: "Invalid pattern: \(target.pattern)",
                severity: .error
            )
        }

        guard let match = content.firstMatch(of: regex),
            match.count > 1,
            let captureRange = match[1].range
        else {
            return HookDiagnostic(
                file: target.file,
                message: "Version pattern not found in file",
                severity: .error
            )
        }

        // Get the captured version
        let foundVersion = String(content[captureRange])

        if foundVersion != expectedVersion {
            return HookDiagnostic(
                file: target.file,
                message: "Version mismatch: found '\(foundVersion)', expected '\(expectedVersion)'",
                severity: .error,
                fixable: true
            )
        }

        return nil
    }

    private func fixTarget(
        _ target: SyncTarget,
        version: String,
        context: HookContext
    ) throws -> Bool {
        let targetURL = context.projectRoot.appendingPathComponent(target.file)

        guard FileManager.default.fileExists(atPath: targetURL.path) else {
            return false
        }

        var content = try String(contentsOf: targetURL, encoding: .utf8)

        // Create regex from pattern
        guard let regex = try? Regex(target.pattern) else {
            return false
        }

        guard let match = content.firstMatch(of: regex),
            match.count > 1,
            let versionRange = match[1].range
        else {
            return false
        }

        let foundVersion = String(content[versionRange])
        if foundVersion == version {
            return false  // Already correct
        }

        // Replace the version
        content.replaceSubrange(versionRange, with: version)

        try content.write(to: targetURL, atomically: true, encoding: .utf8)
        return true
    }
}

// MARK: - VersionSyncError

enum VersionSyncError: Error {
    case sourceNotFound(String)
    case emptyVersion(String)
}

// MARK: - Default Configurations

extension VersionSyncTask {
    /// Common Swift package version sync configuration
    /// Uses .spk.json as version source by default
    public static func swiftPackage(
        source: VersionSource = .spk,
        mainFile: String = "Sources/*/main.swift",
        versionPattern: String = #"version: "(\d+\.\d+\.\d+)""#
    ) -> Self {
        Self(
            source: source,
            syncTargets: [
                SyncTarget(file: mainFile, pattern: versionPattern),
                SyncTarget(file: "README.md", pattern: #"from: "(\d+\.\d+\.\d+)""#),
            ]
        )
    }
}

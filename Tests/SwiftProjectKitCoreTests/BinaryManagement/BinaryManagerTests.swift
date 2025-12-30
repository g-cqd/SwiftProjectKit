// BinaryManagerTests.swift
// Tests for BinaryManager actor functionality.
//
// ## Test Goals
// - Verify binary path construction is correct
// - Test cache detection works properly
// - Ensure cached binaries are returned without downloading
// - Validate download and extraction flow
// - Test error handling for failures
// - Verify cache clearing functionality
//
// ## Why These Tests Matter
// BinaryManager is responsible for downloading and caching tool binaries.
// Bugs here cause builds to fail or re-download binaries unnecessarily.

import Foundation
import Testing

@testable import SwiftProjectKitCore

@Suite("BinaryManager Tests")
struct BinaryManagerTests {
    // MARK: Internal

    let cacheDirectory = URL(fileURLWithPath: "/tmp/test-cache")

    // MARK: - Binary Path Construction

    @Test("Binary path is correctly constructed")
    func binaryPathConstruction() async {
        let manager = createManager()

        let path = await manager.binaryPath(for: .swa, version: "0.1.0")

        #expect(path.path.contains("bin"), "Path should contain 'bin' directory")
        #expect(path.path.contains("swa"), "Path should contain tool name")
        #expect(path.path.contains("0.1.0"), "Path should contain version")
        #expect(path.lastPathComponent == "swa", "Should end with binary name")
    }

    @Test("Binary path includes cache directory")
    func binaryPathIncludesCacheDirectory() async {
        let manager = createManager()

        let path = await manager.binaryPath(for: .swa, version: "0.1.0")

        #expect(
            path.path.hasPrefix(cacheDirectory.path),
            "Path should start with cache directory"
        )
    }

    @Test("Different versions have different paths")
    func differentVersionsDifferentPaths() async {
        let manager = createManager()

        let path1 = await manager.binaryPath(for: .swa, version: "0.1.0")
        let path2 = await manager.binaryPath(for: .swa, version: "0.2.0")

        #expect(path1 != path2, "Different versions should have different paths")
    }

    // MARK: - Cache Detection

    @Test("isCached returns false when binary doesn't exist")
    func isCachedReturnsFalseWhenNotExists() async {
        let fileSystem = MockFileSystem()
        let manager = createManager(fileSystem: fileSystem)

        let isCached = await manager.isCached(tool: .swa)

        #expect(!isCached, "Should not be cached when file doesn't exist")
    }

    @Test("isCached returns true when binary exists")
    func isCachedReturnsTrueWhenExists() async {
        let fileSystem = MockFileSystem()
        let manager = createManager(fileSystem: fileSystem)

        let binaryPath = await manager.binaryPath(
            for: .swa,
            version: ManagedTool.swa.defaultVersion
        )
        fileSystem.addExistingPath(binaryPath.path)

        let isCached = await manager.isCached(tool: .swa)

        #expect(isCached, "Should be cached when file exists")
    }

    @Test("isCached uses default version when not specified")
    func isCachedUsesDefaultVersion() async {
        let fileSystem = MockFileSystem()
        let manager = createManager(fileSystem: fileSystem)

        let defaultPath = await manager.binaryPath(
            for: .swa,
            version: ManagedTool.swa.defaultVersion
        )
        fileSystem.addExistingPath(defaultPath.path)

        let isCached = await manager.isCached(tool: .swa)

        #expect(isCached)
    }

    // MARK: - Cached Binary Return

    @Test("Returns cached binary without downloading")
    func returnsCachedBinaryWithoutDownloading() async throws {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let manager = createManager(fileSystem: fileSystem, networkSession: networkSession)

        let binaryPath = await manager.binaryPath(for: .swa, version: "0.1.0")
        fileSystem.addExistingPath(binaryPath.path)

        let result = try await manager.ensureBinary(for: .swa, version: "0.1.0")

        #expect(result == binaryPath)

        let downloadedURLs = await networkSession.downloadedURLs
        #expect(downloadedURLs.isEmpty, "Should not download when cached")
    }

    // MARK: - Download and Extract

    @Test("Downloads and extracts when not cached")
    func downloadsWhenNotCached() async throws {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let tempFile = URL(fileURLWithPath: "/tmp/downloaded.zip")
        await networkSession.setResponse(localURL: tempFile, httpStatusCode: 200)

        let manager = createManager(
            fileSystem: fileSystem,
            networkSession: networkSession,
            extractor: extractor
        )

        let binaryPath = await manager.binaryPath(for: .swa, version: "0.1.0")

        await extractor.setOnExtract { _, _ in
            fileSystem.addExistingPath(binaryPath.path)
            fileSystem.setAttributes([.posixPermissions: 0o644], for: binaryPath.path)
        }

        let result = try await manager.ensureBinary(for: .swa, version: "0.1.0")

        #expect(result == binaryPath)

        let downloadedURLs = await networkSession.downloadedURLs
        #expect(downloadedURLs.count == 1)
        #expect(downloadedURLs.first?.absoluteString.contains("swa") == true)

        let extracted = await extractor.getExtractedArchives()
        #expect(extracted.count == 1)
    }

    // MARK: - Error Handling

    @Test("Throws error on download failure")
    func throwsOnDownloadFailure() async {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let tempFile = URL(fileURLWithPath: "/tmp/downloaded.zip")
        await networkSession.setResponse(localURL: tempFile, httpStatusCode: 404)

        let manager = createManager(
            fileSystem: fileSystem,
            networkSession: networkSession,
            extractor: extractor
        )

        do {
            _ = try await manager.ensureBinary(for: .swa, version: "0.1.0")
            Issue.record("Expected error to be thrown")
        } catch let error as BinaryManagerError {
            if case .downloadFailed(let tool, let version, let statusCode) = error {
                #expect(tool == .swa)
                #expect(version == "0.1.0")
                #expect(statusCode == 404)
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Throws error on extraction failure")
    func throwsOnExtractionFailure() async {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let tempFile = URL(fileURLWithPath: "/tmp/downloaded.zip")
        await networkSession.setResponse(localURL: tempFile, httpStatusCode: 200)
        await extractor.setShouldFail(true, message: "Corrupt archive")

        let manager = createManager(
            fileSystem: fileSystem,
            networkSession: networkSession,
            extractor: extractor
        )

        do {
            _ = try await manager.ensureBinary(for: .swa, version: "0.1.0")
            Issue.record("Expected error to be thrown")
        } catch let error as BinaryManagerError {
            if case .extractionFailed(let tool, _) = error {
                #expect(tool == .swa)
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Throws error when binary not found after extraction")
    func throwsWhenBinaryNotFoundAfterExtraction() async {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let tempFile = URL(fileURLWithPath: "/tmp/downloaded.zip")
        await networkSession.setResponse(localURL: tempFile, httpStatusCode: 200)

        let manager = createManager(
            fileSystem: fileSystem,
            networkSession: networkSession,
            extractor: extractor
        )

        do {
            _ = try await manager.ensureBinary(for: .swa, version: "0.1.0")
            Issue.record("Expected error to be thrown")
        } catch let error as BinaryManagerError {
            if case .binaryNotFound(let tool, _) = error {
                #expect(tool == .swa)
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    // MARK: - Cache Clearing

    @Test("clearCache removes cached binary")
    func clearCacheRemovesBinary() async throws {
        let fileSystem = MockFileSystem()
        let manager = createManager(fileSystem: fileSystem)

        let binaryPath = await manager.binaryPath(for: .swa, version: "0.1.0")
        let versionDir = binaryPath.deletingLastPathComponent()
        fileSystem.addExistingPath(versionDir.path)

        try await manager.clearCache(for: .swa, version: "0.1.0")

        #expect(fileSystem.removedItems.contains(versionDir))
    }

    @Test("clearAllCaches removes bin directory")
    func clearAllCachesRemovesBinDirectory() async throws {
        let fileSystem = MockFileSystem()
        let manager = createManager(fileSystem: fileSystem)

        let binPath = cacheDirectory.appendingPathComponent("bin")
        fileSystem.addExistingPath(binPath.path)

        try await manager.clearAllCaches()

        #expect(fileSystem.removedItems.contains(binPath))
    }

    @Test("clearCache does nothing when not cached")
    func clearCacheDoesNothingWhenNotCached() async throws {
        let fileSystem = MockFileSystem()
        let manager = createManager(fileSystem: fileSystem)

        try await manager.clearCache(for: .swa, version: "0.1.0")

        #expect(fileSystem.removedItems.isEmpty)
    }

    // MARK: Private

    // MARK: - Helpers

    private func createManager(
        fileSystem: MockFileSystem = MockFileSystem(),
        networkSession: MockNetworkSession = MockNetworkSession(),
        extractor: MockArchiveExtractor = MockArchiveExtractor()
    ) -> BinaryManager {
        BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor
        )
    }
}

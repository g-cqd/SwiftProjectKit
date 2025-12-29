import Foundation
@testable import SwiftProjectKitCore
import Testing

// MARK: - ManagedToolTests

@Suite("ManagedTool Tests")
struct ManagedToolTests {
    @Test("All tools have valid repository format")
    func repositoryFormat() {
        for tool in ManagedTool.allCases {
            let repo = tool.repository
            #expect(repo.contains("/"), "Repository should be in 'owner/repo' format")
            #expect(repo.split(separator: "/").count == 2, "Repository should have exactly one slash")
        }
    }

    @Test("All tools have non-empty binary names")
    func binaryNames() {
        for tool in ManagedTool.allCases {
            #expect(!tool.binaryName.isEmpty)
            #expect(tool.binaryName == tool.rawValue, "Binary name should match raw value")
        }
    }

    @Test("All tools have valid default versions")
    func defaultVersions() {
        for tool in ManagedTool.allCases {
            let version = tool.defaultVersion
            #expect(!version.isEmpty)
            // Version should be semantic versioning format
            #expect(version.split(separator: ".").count >= 2, "Version should be semantic")
        }
    }

    @Test("SwiftLint download URL is correct")
    func swiftLintDownloadURL() {
        let tool = ManagedTool.swiftlint
        let url = tool.downloadURL(for: "0.57.1")

        #expect(url.absoluteString.contains("github.com"))
        #expect(url.absoluteString.contains("realm/SwiftLint"))
        #expect(url.absoluteString.contains("0.57.1"))
        #expect(url.absoluteString.contains("portable_swiftlint.zip"))
    }

    @Test("SwiftFormat download URL is correct")
    func swiftFormatDownloadURL() {
        let tool = ManagedTool.swiftformat
        let url = tool.downloadURL(for: "0.54.6")

        #expect(url.absoluteString.contains("github.com"))
        #expect(url.absoluteString.contains("nicklockwood/SwiftFormat"))
        #expect(url.absoluteString.contains("0.54.6"))
        #expect(url.absoluteString.contains("swiftformat.zip"))
    }

    @Test("Asset names are correct for each tool")
    func assetNames() {
        #expect(ManagedTool.swiftlint.assetName(for: "1.0.0") == "portable_swiftlint.zip")
        #expect(ManagedTool.swiftformat.assetName(for: "1.0.0") == "swiftformat.zip")
    }
}

// MARK: - BinaryManagerErrorTests

@Suite("BinaryManagerError Tests")
struct BinaryManagerErrorTests {
    @Test("Error descriptions are meaningful")
    func errorDescriptions() {
        let downloadError = BinaryManagerError.downloadFailed(tool: .swiftlint, version: "1.0.0", statusCode: 404)
        #expect(downloadError.description.contains("swiftlint"))
        #expect(downloadError.description.contains("1.0.0"))
        #expect(downloadError.description.contains("404"))

        let extractionError = BinaryManagerError.extractionFailed(tool: .swiftformat, reason: "corrupt archive")
        #expect(extractionError.description.contains("swiftformat"))
        #expect(extractionError.description.contains("corrupt archive"))

        let notFoundError = BinaryManagerError.binaryNotFound(tool: .swiftlint, path: "/some/path")
        #expect(notFoundError.description.contains("swiftlint"))
        #expect(notFoundError.description.contains("/some/path"))

        let permissionError = BinaryManagerError.permissionDenied(path: "/protected")
        #expect(permissionError.description.contains("/protected"))

        let networkError = BinaryManagerError.networkUnavailable
        #expect(!networkError.description.isEmpty)
    }

    @Test("Errors are equatable")
    func errorEquality() {
        let error1 = BinaryManagerError.downloadFailed(tool: .swiftlint, version: "1.0.0", statusCode: 404)
        let error2 = BinaryManagerError.downloadFailed(tool: .swiftlint, version: "1.0.0", statusCode: 404)
        let error3 = BinaryManagerError.downloadFailed(tool: .swiftlint, version: "1.0.1", statusCode: 404)

        #expect(error1 == error2)
        #expect(error1 != error3)
    }
}

// MARK: - BinaryManagerTests

@Suite("BinaryManager Tests")
struct BinaryManagerTests {
    let cacheDirectory = URL(fileURLWithPath: "/tmp/test-cache")

    @Test("Binary path is correctly constructed")
    func testBinaryPath() async {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        let path = await manager.binaryPath(for: .swiftlint, version: "0.57.1")

        #expect(path.path.contains("bin"))
        #expect(path.path.contains("swiftlint"))
        #expect(path.path.contains("0.57.1"))
        #expect(path.lastPathComponent == "swiftlint")
    }

    @Test("Returns cached binary without downloading")
    func returnsCachedBinary() async throws {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        // Pre-cache the binary path
        let binaryPath = await manager.binaryPath(for: .swiftlint, version: "0.57.1")
        fileSystem.addExistingPath(binaryPath.path)

        // Should return cached without downloading
        let result = try await manager.ensureBinary(for: .swiftlint, version: "0.57.1")

        #expect(result == binaryPath)
        let downloadedURLs = await networkSession.downloadedURLs
        #expect(downloadedURLs.isEmpty, "Should not download when cached")
    }

    @Test("isCached returns correct status")
    func testIsCached() async {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        // Not cached initially
        var isCached = await manager.isCached(tool: .swiftlint)
        #expect(!isCached)

        // Add to cache
        let binaryPath = await manager.binaryPath(for: .swiftlint, version: ManagedTool.swiftlint.defaultVersion)
        fileSystem.addExistingPath(binaryPath.path)

        // Now should be cached
        isCached = await manager.isCached(tool: .swiftlint)
        #expect(isCached)
    }

    @Test("Downloads and extracts when not cached")
    func downloadsWhenNotCached() async throws {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        // Configure mock to simulate successful download
        let tempFile = URL(fileURLWithPath: "/tmp/downloaded.zip")
        await networkSession.setResponse(localURL: tempFile, httpStatusCode: 200)

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        // Get the expected binary path
        let binaryPath = await manager.binaryPath(for: .swiftformat, version: "0.54.6")

        // Configure extractor to simulate creating the binary file during extraction
        await extractor.setOnExtract { _, _ in
            fileSystem.addExistingPath(binaryPath.path)
            fileSystem.setAttributes([.posixPermissions: 0o644], for: binaryPath.path)
        }

        let result = try await manager.ensureBinary(for: .swiftformat, version: "0.54.6")

        #expect(result == binaryPath)
        let downloadedURLs = await networkSession.downloadedURLs
        #expect(downloadedURLs.count == 1)
        #expect(downloadedURLs.first?.absoluteString.contains("swiftformat") == true)

        let extracted = await extractor.getExtractedArchives()
        #expect(extracted.count == 1)
    }

    @Test("Throws error on download failure")
    func throwsOnDownloadFailure() async {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        // Configure mock to return 404
        let tempFile = URL(fileURLWithPath: "/tmp/downloaded.zip")
        await networkSession.setResponse(localURL: tempFile, httpStatusCode: 404)

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        do {
            _ = try await manager.ensureBinary(for: .swiftlint, version: "0.57.1")
            Issue.record("Expected error to be thrown")
        } catch let error as BinaryManagerError {
            if case let .downloadFailed(tool, version, statusCode) = error {
                #expect(tool == .swiftlint)
                #expect(version == "0.57.1")
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

        // Configure successful download but failed extraction
        let tempFile = URL(fileURLWithPath: "/tmp/downloaded.zip")
        await networkSession.setResponse(localURL: tempFile, httpStatusCode: 200)
        await extractor.setShouldFail(true, message: "Corrupt archive")

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        do {
            _ = try await manager.ensureBinary(for: .swiftformat, version: "0.54.6")
            Issue.record("Expected error to be thrown")
        } catch let error as BinaryManagerError {
            if case let .extractionFailed(tool, _) = error {
                #expect(tool == .swiftformat)
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Throws error when binary not found after extraction")
    func throwsWhenBinaryNotFound() async {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        // Configure successful download and extraction, but binary doesn't exist
        let tempFile = URL(fileURLWithPath: "/tmp/downloaded.zip")
        await networkSession.setResponse(localURL: tempFile, httpStatusCode: 200)

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        // Don't add the binary path to existing paths - simulates extraction that didn't produce expected file

        do {
            _ = try await manager.ensureBinary(for: .swiftformat, version: "0.54.6")
            Issue.record("Expected error to be thrown")
        } catch let error as BinaryManagerError {
            if case let .binaryNotFound(tool, _) = error {
                #expect(tool == .swiftformat)
            } else {
                Issue.record("Wrong error type: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("clearCache removes cached binary")
    func testClearCache() async throws {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        // Add cached binary
        let binaryPath = await manager.binaryPath(for: .swiftlint, version: "0.57.1")
        let versionDir = binaryPath.deletingLastPathComponent()
        fileSystem.addExistingPath(versionDir.path)

        try await manager.clearCache(for: .swiftlint, version: "0.57.1")

        #expect(fileSystem.removedItems.contains(versionDir))
    }

    @Test("clearAllCaches removes bin directory")
    func testClearAllCaches() async throws {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        // Add bin directory
        let binPath = cacheDirectory.appendingPathComponent("bin")
        fileSystem.addExistingPath(binPath.path)

        try await manager.clearAllCaches()

        #expect(fileSystem.removedItems.contains(binPath))
    }

    @Test("Uses default version when not specified")
    func usesDefaultVersion() async {
        let fileSystem = MockFileSystem()
        let networkSession = MockNetworkSession()
        let extractor = MockArchiveExtractor()

        let manager = BinaryManager(
            cacheDirectory: cacheDirectory,
            fileSystem: fileSystem,
            networkSession: networkSession,
            archiveExtractor: extractor,
        )

        // Check isCached with no version
        let defaultPath = await manager.binaryPath(for: .swiftlint, version: ManagedTool.swiftlint.defaultVersion)
        fileSystem.addExistingPath(defaultPath.path)

        let isCached = await manager.isCached(tool: .swiftlint)
        #expect(isCached)
    }
}

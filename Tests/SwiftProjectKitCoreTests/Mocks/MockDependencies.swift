import Foundation
@testable import SwiftProjectKitCore

// MARK: - MockFileSystem

/// Mock file system for testing - tracks all operations
final class MockFileSystem: FileSystem, @unchecked Sendable {
    // MARK: Internal

    var existingPaths: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return _existingPaths
    }

    var createdDirectories: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _createdDirectories
    }

    var removedItems: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _removedItems
    }

    var movedItems: [(from: URL, to: URL)] {
        lock.lock()
        defer { lock.unlock() }
        return _movedItems
    }

    func addExistingPath(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        _existingPaths.insert(path)
    }

    func setDirectoryContents(_ contents: [URL], for directory: URL) {
        lock.lock()
        defer { lock.unlock() }
        _directoryContents[directory] = contents
    }

    func setAttributes(_ attrs: [FileAttributeKey: Any], for path: String) {
        lock.lock()
        defer { lock.unlock() }
        _attributes[path] = attrs
    }

    // MARK: - FileSystem Protocol

    func fileExists(atPath path: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _existingPaths.contains(path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        _createdDirectories.append(url)
        _existingPaths.insert(url.path)
    }

    func removeItem(at url: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        _removedItems.append(url)
        _existingPaths.remove(url.path)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        _movedItems.append((from: srcURL, to: dstURL))
        _existingPaths.remove(srcURL.path)
        _existingPaths.insert(dstURL.path)
    }

    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        lock.lock()
        defer { lock.unlock() }
        return _attributes[path] ?? [.posixPermissions: 0o644]
    }

    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        _attributes[path] = attributes
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _directoryContents[url] ?? []
    }

    // MARK: Private

    private let lock = NSLock()

    private var _existingPaths: Set<String> = []
    private var _createdDirectories: [URL] = []
    private var _removedItems: [URL] = []
    private var _movedItems: [(from: URL, to: URL)] = []
    private var _attributes: [String: [FileAttributeKey: Any]] = [:]
    private var _directoryContents: [URL: [URL]] = [:]
}

// MARK: - MockNetworkSession

/// Mock network session for testing downloads
actor MockNetworkSession: NetworkSession {
    // MARK: Internal

    var downloadedURLs: [URL] {
        _downloadedURLs
    }

    func setResponse(localURL: URL, httpStatusCode: Int) {
        guard let mockURL = URL(string: "https://example.com"),
              let response = HTTPURLResponse(
                  url: mockURL,
                  statusCode: httpStatusCode,
                  httpVersion: nil,
                  headerFields: nil
              )
        else {
            fatalError("Test configuration error: Failed to create mock URL or HTTPURLResponse")
        }
        _responseToReturn = (localURL, response)
    }

    func setError(_ error: Error) {
        _errorToThrow = error
    }

    nonisolated func download(from url: URL) async throws -> (URL, URLResponse) {
        try await _download(from: url)
    }

    // MARK: Private

    private var _downloadedURLs: [URL] = []
    private var _responseToReturn: (URL, URLResponse)?
    private var _errorToThrow: Error?

    private func _download(from url: URL) async throws -> (URL, URLResponse) {
        _downloadedURLs.append(url)

        if let error = _errorToThrow {
            throw error
        }

        guard let response = _responseToReturn else {
            throw NSError(
                domain: "MockError",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No mock response configured"],
            )
        }

        return response
    }
}

// MARK: - MockArchiveExtractor

/// Mock archive extractor for testing
actor MockArchiveExtractor: ArchiveExtractor {
    // MARK: Internal

    func getExtractedArchives() -> [(source: URL, destination: URL)] {
        extractedArchives
    }

    func setShouldFail(_ fail: Bool, message: String = "Mock extraction failed") {
        shouldFail = fail
        errorMessage = message
    }

    /// Set a callback to run when extraction occurs (useful for simulating file creation)
    func setOnExtract(_ callback: @escaping (URL, URL) -> Void) {
        onExtract = callback
    }

    func extract(zipAt source: URL, to destination: URL) async throws {
        extractedArchives.append((source: source, destination: destination))
        if shouldFail {
            throw ArchiveExtractorError.extractionFailed(reason: errorMessage)
        }
        onExtract?(source, destination)
    }

    // MARK: Private

    private var extractedArchives: [(source: URL, destination: URL)] = []
    private var shouldFail = false
    private var errorMessage = "Mock extraction failed"
    private var onExtract: ((URL, URL) -> Void)?
}

// MARK: - MockError

enum MockError: Error {
    case networkError
    case fileSystemError
}

import Foundation

// MARK: - NetworkSession

/// Protocol for network operations - enables dependency injection for testing
public protocol NetworkSession: Sendable {
    func download(from url: URL) async throws -> (URL, URLResponse)
}

// MARK: - URLSession + NetworkSession

extension URLSession: NetworkSession {
    public func download(from url: URL) async throws -> (URL, URLResponse) {
        try await download(from: url, delegate: nil)
    }
}

// MARK: - FileSystem

/// Protocol for file system operations - enables dependency injection for testing
public protocol FileSystem: Sendable {
    func fileExists(atPath path: String) -> Bool
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws
    func removeItem(at url: URL) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any]
    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws
    func contentsOfDirectory(at url: URL) throws -> [URL]
}

// MARK: - DefaultFileSystem

/// Default implementation wrapping FileManager.
/// `@unchecked Sendable` is safe here because `FileManager` is documented to be thread-safe for file operations.
public final class DefaultFileSystem: FileSystem, @unchecked Sendable {
    // MARK: Lifecycle

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: Public

    public func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    public func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories)
    }

    public func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    public func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try fileManager.moveItem(at: srcURL, to: dstURL)
    }

    public func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        try fileManager.attributesOfItem(atPath: path)
    }

    public func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        try fileManager.setAttributes(attributes, ofItemAtPath: path)
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    // MARK: Private

    private let fileManager: FileManager
}

// MARK: - ArchiveExtractor

/// Protocol for archive extraction - enables dependency injection for testing
public protocol ArchiveExtractor: Sendable {
    func extract(zipAt source: URL, to destination: URL) async throws
}

// MARK: - DefaultArchiveExtractor

/// Default implementation using /usr/bin/unzip
public actor DefaultArchiveExtractor: ArchiveExtractor {
    // MARK: Lifecycle

    public init() {}

    // MARK: Public

    public func extract(zipAt source: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", source.path, "-d", destination.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown extraction error"
            throw ArchiveExtractorError.extractionFailed(reason: errorMessage)
        }
    }
}

// MARK: - ArchiveExtractorError

public enum ArchiveExtractorError: Error, Sendable {
    case extractionFailed(reason: String)
}

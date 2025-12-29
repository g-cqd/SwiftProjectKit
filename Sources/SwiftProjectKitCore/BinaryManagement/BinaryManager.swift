import Foundation

// MARK: - ManagedTool

/// Supported tools that can be downloaded and managed
public enum ManagedTool: String, Sendable, CaseIterable {
    case swiftlint
    case swiftformat

    // MARK: Public

    /// GitHub repository in "owner/repo" format
    public var repository: String {
        switch self {
        case .swiftlint: "realm/SwiftLint"
        case .swiftformat: "nicklockwood/SwiftFormat"
        }
    }

    /// Binary name inside the downloaded archive
    public var binaryName: String {
        rawValue
    }

    /// Default pinned version
    public var defaultVersion: String {
        switch self {
        case .swiftlint: "0.57.1"
        case .swiftformat: "0.54.6"
        }
    }

    /// Asset name pattern for macOS universal binary
    public func assetName(for version: String) -> String {
        switch self {
        case .swiftlint:
            "portable_swiftlint.zip"

        case .swiftformat:
            "swiftformat.zip"
        }
    }

    /// Download URL for a specific version
    public func downloadURL(for version: String) -> URL {
        let tag = version.hasPrefix("v") ? version : version
        let asset = assetName(for: version)
        // swiftlint:disable:next force_unwrapping
        return URL(string: "https://github.com/\(repository)/releases/download/\(tag)/\(asset)")!
    }
}

// MARK: - BinaryManagerError

/// Errors that can occur during binary management
public enum BinaryManagerError: Error, Sendable, CustomStringConvertible, Equatable {
    case downloadFailed(tool: ManagedTool, version: String, statusCode: Int)
    case extractionFailed(tool: ManagedTool, reason: String)
    case binaryNotFound(tool: ManagedTool, path: String)
    case permissionDenied(path: String)
    case networkUnavailable

    // MARK: Public

    public var description: String {
        switch self {
        case let .downloadFailed(tool, version, statusCode):
            "Failed to download \(tool.rawValue) v\(version): HTTP \(statusCode)"

        case let .extractionFailed(tool, reason):
            "Failed to extract \(tool.rawValue): \(reason)"

        case let .binaryNotFound(tool, path):
            "\(tool.rawValue) binary not found at \(path)"

        case let .permissionDenied(path):
            "Permission denied: \(path)"

        case .networkUnavailable:
            "Network connection unavailable"
        }
    }
}

// MARK: - BinaryManager

/// Actor responsible for downloading, caching, and managing tool binaries
///
/// Designed for testability with dependency injection for all I/O operations.
public actor BinaryManager {
    // MARK: Lifecycle

    /// Initialize with a cache directory and injectable dependencies
    /// - Parameters:
    ///   - cacheDirectory: Directory to cache downloaded binaries
    ///   - fileSystem: File system abstraction (defaults to real file system)
    ///   - networkSession: Network session for downloads (defaults to URLSession.shared)
    ///   - archiveExtractor: Archive extractor (defaults to unzip-based extractor)
    public init(
        cacheDirectory: URL,
        fileSystem: FileSystem = DefaultFileSystem(),
        networkSession: NetworkSession = URLSession.shared,
        archiveExtractor: ArchiveExtractor = DefaultArchiveExtractor(),
    ) {
        self.cacheDirectory = cacheDirectory
        self.fileSystem = fileSystem
        self.networkSession = networkSession
        self.archiveExtractor = archiveExtractor
    }

    // MARK: Public

    /// Ensure a tool binary is available, downloading if necessary
    /// - Parameters:
    ///   - tool: The tool to ensure
    ///   - version: Version to download (defaults to tool's default version)
    /// - Returns: Path to the executable binary
    public func ensureBinary(
        for tool: ManagedTool,
        version: String? = nil,
    ) async throws -> URL {
        let resolvedVersion = version ?? tool.defaultVersion
        let binaryURL = binaryPath(for: tool, version: resolvedVersion)

        // Check if already cached
        if fileSystem.fileExists(atPath: binaryURL.path) {
            return binaryURL
        }

        // Download and extract
        try await downloadAndExtract(tool: tool, version: resolvedVersion)

        // Verify binary exists
        guard fileSystem.fileExists(atPath: binaryURL.path) else {
            throw BinaryManagerError.binaryNotFound(tool: tool, path: binaryURL.path)
        }

        return binaryURL
    }

    /// Path where a tool binary should be cached
    public func binaryPath(for tool: ManagedTool, version: String) -> URL {
        cacheDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent(tool.rawValue)
            .appendingPathComponent(version)
            .appendingPathComponent(tool.binaryName)
    }

    /// Check if a tool is already cached
    public func isCached(tool: ManagedTool, version: String? = nil) -> Bool {
        let resolvedVersion = version ?? tool.defaultVersion
        let path = binaryPath(for: tool, version: resolvedVersion)
        return fileSystem.fileExists(atPath: path.path)
    }

    /// Remove cached binary for a tool
    public func clearCache(for tool: ManagedTool, version: String? = nil) throws {
        let resolvedVersion = version ?? tool.defaultVersion
        let path = binaryPath(for: tool, version: resolvedVersion).deletingLastPathComponent()
        if fileSystem.fileExists(atPath: path.path) {
            try fileSystem.removeItem(at: path)
        }
    }

    /// Remove all cached binaries
    public func clearAllCaches() throws {
        let binPath = cacheDirectory.appendingPathComponent("bin")
        if fileSystem.fileExists(atPath: binPath.path) {
            try fileSystem.removeItem(at: binPath)
        }
    }

    // MARK: Private

    private let cacheDirectory: URL
    private let fileSystem: FileSystem
    private let networkSession: NetworkSession
    private let archiveExtractor: ArchiveExtractor

    private func downloadAndExtract(tool: ManagedTool, version: String) async throws {
        let downloadURL = tool.downloadURL(for: version)
        let destinationDir = binaryPath(for: tool, version: version).deletingLastPathComponent()

        // Create destination directory
        try fileSystem.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        // Download the archive
        let (localURL, response) = try await networkSession.download(from: downloadURL)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            try? fileSystem.removeItem(at: localURL)
            throw BinaryManagerError.downloadFailed(tool: tool, version: version, statusCode: statusCode)
        }

        // Extract the archive
        do {
            try await archiveExtractor.extract(zipAt: localURL, to: destinationDir)
        } catch {
            try? fileSystem.removeItem(at: localURL)
            throw BinaryManagerError.extractionFailed(tool: tool, reason: error.localizedDescription)
        }

        // Clean up downloaded archive
        try? fileSystem.removeItem(at: localURL)

        // Handle SwiftLint's nested binary location
        if tool == .swiftlint {
            try await relocateSwiftLintBinaryIfNeeded(in: destinationDir)
        }

        // Make binary executable
        let binaryURL = binaryPath(for: tool, version: version)
        try makeExecutable(binaryURL)
    }

    private func relocateSwiftLintBinaryIfNeeded(in directory: URL) async throws {
        let expectedPath = directory.appendingPathComponent("swiftlint")

        guard !fileSystem.fileExists(atPath: expectedPath.path) else {
            return // Already in correct location
        }

        // Look for swiftlint binary in subdirectories
        let contents = try fileSystem.contentsOfDirectory(at: directory)
        for item in contents {
            let potentialBinary = item.appendingPathComponent("swiftlint")
            if fileSystem.fileExists(atPath: potentialBinary.path) {
                try fileSystem.moveItem(at: potentialBinary, to: expectedPath)
                return
            }
        }
    }

    private func makeExecutable(_ url: URL) throws {
        var attributes = try fileSystem.attributesOfItem(atPath: url.path)
        attributes[.posixPermissions] = 0o755
        try fileSystem.setAttributes(attributes, ofItemAtPath: url.path)
    }
}

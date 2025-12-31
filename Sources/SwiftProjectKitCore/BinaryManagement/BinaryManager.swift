import Foundation

// MARK: - ManagedTool

/// Supported tools that can be downloaded and managed
public enum ManagedTool: String, Sendable, CaseIterable {
    case swa

    // MARK: Public

    /// GitHub repository in "owner/repo" format
    public var repository: String {
        switch self {
        case .swa: "g-cqd/SwiftStaticAnalysis"
        }
    }

    /// Binary name inside the downloaded archive
    public var binaryName: String {
        switch self {
        case .swa: "swa"
        }
    }

    /// Default pinned version
    public var defaultVersion: String {
        switch self {
        case .swa: "0.0.16"
        }
    }

    /// Asset name pattern for macOS universal binary
    public func assetName(for version: String) -> String {
        switch self {
        case .swa:
            "swa-\(version)-macos-universal.tar.gz"
        }
    }

    /// Download URL for a specific version
    public func downloadURL(for version: String) -> URL {
        let tag = version.hasPrefix("v") ? version : "v\(version)"
        let asset = assetName(for: version)
        // swift-format-ignore: NeverForceUnwrap
        // URL is constructed from known-valid components
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
        case .downloadFailed(let tool, let version, let statusCode):
            "Failed to download \(tool.rawValue) v\(version): HTTP \(statusCode)"

        case .extractionFailed(let tool, let reason):
            "Failed to extract \(tool.rawValue): \(reason)"

        case .binaryNotFound(let tool, let path):
            "\(tool.rawValue) binary not found at \(path)"

        case .permissionDenied(let path):
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
        let (tempURL, response) = try await networkSession.download(from: downloadURL)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse,
            (200 ... 299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            try? fileSystem.removeItem(at: tempURL)
            throw BinaryManagerError.downloadFailed(tool: tool, version: version, statusCode: statusCode)
        }

        // Rename temp file to preserve extension for extraction type detection
        let archiveFilename = downloadURL.lastPathComponent
        let localURL = tempURL.deletingLastPathComponent().appendingPathComponent(archiveFilename)
        do {
            try fileSystem.moveItem(at: tempURL, to: localURL)
        } catch {
            // If rename fails, use temp URL directly
            try await extractAndCleanup(
                archiveURL: tempURL,
                destinationDir: destinationDir,
                tool: tool,
                version: version
            )
            return
        }

        try await extractAndCleanup(
            archiveURL: localURL,
            destinationDir: destinationDir,
            tool: tool,
            version: version
        )
    }

    private func extractAndCleanup(
        archiveURL: URL,
        destinationDir: URL,
        tool: ManagedTool,
        version: String
    ) async throws {
        // Extract the archive
        do {
            try await archiveExtractor.extract(zipAt: archiveURL, to: destinationDir)
        } catch {
            try? fileSystem.removeItem(at: archiveURL)
            throw BinaryManagerError.extractionFailed(tool: tool, reason: error.localizedDescription)
        }

        // Clean up downloaded archive
        try? fileSystem.removeItem(at: archiveURL)

        // Make binary executable
        let binaryURL = binaryPath(for: tool, version: version)
        try makeExecutable(binaryURL)
    }

    private func makeExecutable(_ url: URL) throws {
        var attributes = try fileSystem.attributesOfItem(atPath: url.path)
        attributes[.posixPermissions] = 0o755
        try fileSystem.setAttributes(attributes, ofItemAtPath: url.path)
    }
}

// ManagedToolTests.swift
// Tests for ManagedTool enum correctness.
//
// ## Test Goals
// - Verify all tools have valid GitHub repository format
// - Ensure binary names match expected values
// - Validate default versions are semantic versioning format
// - Test download URL construction produces valid URLs
// - Confirm asset names are correct for each tool
//
// ## Why These Tests Matter
// ManagedTool drives binary downloads. Invalid repository formats, URLs,
// or asset names cause download failures and break builds.

import Foundation
import Testing

@testable import SwiftProjectKitCore

@Suite("ManagedTool Tests")
struct ManagedToolTests {
    // MARK: - Repository Format

    @Test("All tools have valid repository format")
    func allToolsHaveValidRepositoryFormat() {
        for tool in ManagedTool.allCases {
            let repo = tool.repository

            #expect(repo.contains("/"), "Repository '\(repo)' should contain '/'")

            let parts = repo.split(separator: "/")
            #expect(
                parts.count == 2,
                "Repository '\(repo)' should be in 'owner/repo' format"
            )

            #expect(
                !parts[0].isEmpty,
                "Repository '\(repo)' owner should not be empty"
            )
            #expect(
                !parts[1].isEmpty,
                "Repository '\(repo)' name should not be empty"
            )
        }
    }

    @Test("SWA has correct repository")
    func swaRepository() {
        let tool = ManagedTool.swa

        #expect(tool.repository == "nicklockwood/SwiftStaticAnalysis")
    }

    // MARK: - Binary Names

    @Test("All tools have non-empty binary names")
    func allToolsHaveNonEmptyBinaryNames() {
        for tool in ManagedTool.allCases {
            #expect(!tool.binaryName.isEmpty, "\(tool) should have non-empty binary name")
        }
    }

    @Test("Binary names match raw values")
    func binaryNamesMatchRawValues() {
        for tool in ManagedTool.allCases {
            #expect(
                tool.binaryName == tool.rawValue,
                "Binary name should match raw value for \(tool)"
            )
        }
    }

    @Test("SWA binary name is swa")
    func swaBinaryName() {
        #expect(ManagedTool.swa.binaryName == "swa")
    }

    // MARK: - Default Versions

    @Test("All tools have non-empty default versions")
    func allToolsHaveDefaultVersions() {
        for tool in ManagedTool.allCases {
            #expect(
                !tool.defaultVersion.isEmpty,
                "\(tool) should have non-empty default version"
            )
        }
    }

    @Test("Default versions are semantic versioning format")
    func defaultVersionsAreSemanticFormat() {
        let semverPattern = #"^\d+\.\d+(\.\d+)?$"#

        for tool in ManagedTool.allCases {
            let version = tool.defaultVersion

            let regex = try? NSRegularExpression(pattern: semverPattern)
            let range = NSRange(version.startIndex..., in: version)
            let match = regex?.firstMatch(in: version, range: range)

            #expect(
                match != nil,
                "Version '\(version)' for \(tool) should be semantic versioning (X.Y or X.Y.Z)"
            )
        }
    }

    @Test("SWA default version is pinned")
    func swaDefaultVersion() {
        let version = ManagedTool.swa.defaultVersion

        #expect(version == "0.1.0", "SWA should be pinned to 0.1.0")
    }

    // MARK: - Asset Names

    @Test("SWA asset name is swa.zip")
    func swaAssetName() {
        let assetName = ManagedTool.swa.assetName(for: "1.0.0")

        #expect(assetName == "swa.zip")
    }

    @Test("Asset names are consistent across versions")
    func assetNamesConsistentAcrossVersions() {
        for tool in ManagedTool.allCases {
            let v1 = tool.assetName(for: "1.0.0")
            let v2 = tool.assetName(for: "2.0.0")

            #expect(v1 == v2, "Asset name for \(tool) should be version-independent")
        }
    }

    // MARK: - Download URLs

    @Test("SWA download URL is correctly constructed")
    func swaDownloadURL() {
        let tool = ManagedTool.swa
        let url = tool.downloadURL(for: "0.1.0")

        #expect(url.absoluteString.contains("github.com"))
        #expect(url.absoluteString.contains("nicklockwood/SwiftStaticAnalysis"))
        #expect(url.absoluteString.contains("0.1.0"))
        #expect(url.absoluteString.contains("swa.zip"))
    }

    @Test("Download URLs are HTTPS")
    func downloadURLsAreHTTPS() {
        for tool in ManagedTool.allCases {
            let url = tool.downloadURL(for: tool.defaultVersion)

            #expect(
                url.scheme == "https",
                "Download URL for \(tool) should use HTTPS"
            )
        }
    }

    @Test("Download URLs point to releases")
    func downloadURLsPointToReleases() {
        for tool in ManagedTool.allCases {
            let url = tool.downloadURL(for: tool.defaultVersion)

            #expect(
                url.absoluteString.contains("/releases/download/"),
                "URL for \(tool) should point to releases"
            )
        }
    }

    @Test("Download URLs are valid")
    func downloadURLsAreValid() {
        for tool in ManagedTool.allCases {
            let url = tool.downloadURL(for: tool.defaultVersion)

            #expect(url.host != nil, "URL for \(tool) should have valid host")
            #expect(url.path.count > 1, "URL for \(tool) should have valid path")
        }
    }
}

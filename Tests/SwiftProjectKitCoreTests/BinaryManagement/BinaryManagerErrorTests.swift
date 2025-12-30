// BinaryManagerErrorTests.swift
// Tests for BinaryManagerError enum correctness.
//
// ## Test Goals
// - Verify all error cases have meaningful descriptions
// - Ensure error descriptions contain relevant context
// - Test Equatable conformance for error comparison
//
// ## Why These Tests Matter
// Clear error messages help users diagnose and fix issues.
// Meaningful error descriptions reduce support burden.

import Foundation
import Testing

@testable import SwiftProjectKitCore

@Suite("BinaryManagerError Tests")
struct BinaryManagerErrorTests {
    // MARK: - Error Descriptions

    @Test("downloadFailed error has meaningful description")
    func downloadFailedDescription() {
        let error = BinaryManagerError.downloadFailed(
            tool: .swa,
            version: "1.0.0",
            statusCode: 404
        )

        let description = error.description

        #expect(description.contains("swa"), "Should mention tool name")
        #expect(description.contains("1.0.0"), "Should mention version")
        #expect(description.contains("404"), "Should mention status code")
    }

    @Test("extractionFailed error has meaningful description")
    func extractionFailedDescription() {
        let error = BinaryManagerError.extractionFailed(
            tool: .swa,
            reason: "corrupt archive"
        )

        let description = error.description

        #expect(description.contains("swa"), "Should mention tool name")
        #expect(description.contains("corrupt archive"), "Should mention reason")
    }

    @Test("binaryNotFound error has meaningful description")
    func binaryNotFoundDescription() {
        let error = BinaryManagerError.binaryNotFound(
            tool: .swa,
            path: "/some/path/swa"
        )

        let description = error.description

        #expect(description.contains("swa"), "Should mention tool name")
        #expect(description.contains("/some/path"), "Should mention path")
    }

    @Test("permissionDenied error has meaningful description")
    func permissionDeniedDescription() {
        let error = BinaryManagerError.permissionDenied(path: "/protected/path")

        let description = error.description

        #expect(description.contains("/protected/path"), "Should mention path")
    }

    @Test("networkUnavailable error has description")
    func networkUnavailableDescription() {
        let error = BinaryManagerError.networkUnavailable

        #expect(!error.description.isEmpty, "Should have non-empty description")
    }

    // MARK: - Description Completeness

    @Test("All error descriptions are non-empty")
    func allDescriptionsNonEmpty() {
        let errors: [BinaryManagerError] = [
            .downloadFailed(tool: .swa, version: "1.0", statusCode: 500),
            .extractionFailed(tool: .swa, reason: "test"),
            .binaryNotFound(tool: .swa, path: "/test"),
            .permissionDenied(path: "/test"),
            .networkUnavailable,
        ]

        for error in errors {
            #expect(
                !error.description.isEmpty,
                "\(error) should have non-empty description"
            )
        }
    }

    // MARK: - Equatable Conformance

    @Test("Same downloadFailed errors are equal")
    func sameDownloadFailedErrorsEqual() {
        let error1 = BinaryManagerError.downloadFailed(
            tool: .swa,
            version: "1.0.0",
            statusCode: 404
        )
        let error2 = BinaryManagerError.downloadFailed(
            tool: .swa,
            version: "1.0.0",
            statusCode: 404
        )

        #expect(error1 == error2)
    }

    @Test("Different downloadFailed versions are not equal")
    func differentVersionsNotEqual() {
        let error1 = BinaryManagerError.downloadFailed(
            tool: .swa,
            version: "1.0.0",
            statusCode: 404
        )
        let error2 = BinaryManagerError.downloadFailed(
            tool: .swa,
            version: "1.0.1",
            statusCode: 404
        )

        #expect(error1 != error2)
    }

    @Test("Different downloadFailed status codes are not equal")
    func differentStatusCodesNotEqual() {
        let error1 = BinaryManagerError.downloadFailed(
            tool: .swa,
            version: "1.0.0",
            statusCode: 404
        )
        let error2 = BinaryManagerError.downloadFailed(
            tool: .swa,
            version: "1.0.0",
            statusCode: 500
        )

        #expect(error1 != error2)
    }

    @Test("Same extractionFailed errors are equal")
    func sameExtractionFailedErrorsEqual() {
        let error1 = BinaryManagerError.extractionFailed(
            tool: .swa,
            reason: "corrupt"
        )
        let error2 = BinaryManagerError.extractionFailed(
            tool: .swa,
            reason: "corrupt"
        )

        #expect(error1 == error2)
    }

    @Test("Same binaryNotFound errors are equal")
    func sameBinaryNotFoundErrorsEqual() {
        let error1 = BinaryManagerError.binaryNotFound(
            tool: .swa,
            path: "/test"
        )
        let error2 = BinaryManagerError.binaryNotFound(
            tool: .swa,
            path: "/test"
        )

        #expect(error1 == error2)
    }

    @Test("Same permissionDenied errors are equal")
    func samePermissionDeniedErrorsEqual() {
        let error1 = BinaryManagerError.permissionDenied(path: "/test")
        let error2 = BinaryManagerError.permissionDenied(path: "/test")

        #expect(error1 == error2)
    }

    @Test("networkUnavailable errors are equal")
    func networkUnavailableErrorsEqual() {
        let error1 = BinaryManagerError.networkUnavailable
        let error2 = BinaryManagerError.networkUnavailable

        #expect(error1 == error2)
    }

    @Test("Different error types are not equal")
    func differentErrorTypesNotEqual() {
        let download = BinaryManagerError.downloadFailed(
            tool: .swa,
            version: "1.0",
            statusCode: 404
        )
        let extraction = BinaryManagerError.extractionFailed(
            tool: .swa,
            reason: "test"
        )
        let notFound = BinaryManagerError.binaryNotFound(
            tool: .swa,
            path: "/test"
        )
        let permission = BinaryManagerError.permissionDenied(path: "/test")
        let network = BinaryManagerError.networkUnavailable

        #expect(download != extraction)
        #expect(extraction != notFound)
        #expect(notFound != permission)
        #expect(permission != network)
    }
}

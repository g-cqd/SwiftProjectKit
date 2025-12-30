// WorkflowConfigurationTests.swift
// Tests for WorkflowConfiguration model correctness.
//
// ## Test Goals
// - Verify default initialization enables all workflows
// - Ensure individual workflow flags work correctly
// - Test Codable conformance for serialization
// - Test Equatable conformance for comparisons
//
// ## Why These Tests Matter
// WorkflowConfiguration controls which GitHub Actions workflows are generated.
// Incorrect defaults could lead to missing CI/CD pipelines.

import Foundation
@testable import SwiftProjectKitCore
import Testing

@Suite("WorkflowConfiguration Tests")
struct WorkflowConfigurationTests {
    // MARK: - Default Initialization

    @Test("Default initialization enables CI workflow")
    func defaultEnablesCI() {
        let config = WorkflowConfiguration()

        #expect(config.ci == true, "CI should be enabled by default")
    }

    @Test("Default initialization enables release workflow")
    func defaultEnablesRelease() {
        let config = WorkflowConfiguration()

        #expect(config.release == true, "Release should be enabled by default")
    }

    @Test("Default initialization enables docs workflow")
    func defaultEnablesDocs() {
        let config = WorkflowConfiguration()

        #expect(config.docs == true, "Docs should be enabled by default")
    }

    // MARK: - Custom Initialization

    @Test("Custom initialization sets CI correctly")
    func customInitializationCI() {
        let enabled = WorkflowConfiguration(ci: true, release: false, docs: false)
        let disabled = WorkflowConfiguration(ci: false, release: true, docs: true)

        #expect(enabled.ci == true)
        #expect(disabled.ci == false)
    }

    @Test("Custom initialization sets release correctly")
    func customInitializationRelease() {
        let enabled = WorkflowConfiguration(ci: false, release: true, docs: false)
        let disabled = WorkflowConfiguration(ci: true, release: false, docs: true)

        #expect(enabled.release == true)
        #expect(disabled.release == false)
    }

    @Test("Custom initialization sets docs correctly")
    func customInitializationDocs() {
        let enabled = WorkflowConfiguration(ci: false, release: false, docs: true)
        let disabled = WorkflowConfiguration(ci: true, release: true, docs: false)

        #expect(enabled.docs == true)
        #expect(disabled.docs == false)
    }

    @Test("All false configuration works")
    func allFalseConfiguration() {
        let config = WorkflowConfiguration(ci: false, release: false, docs: false)

        #expect(config.ci == false)
        #expect(config.release == false)
        #expect(config.docs == false)
    }

    // MARK: - Codable Conformance

    @Test("Encodes and decodes correctly")
    func codableRoundTrip() throws {
        let original = WorkflowConfiguration(ci: true, release: false, docs: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkflowConfiguration.self, from: data)

        #expect(decoded == original)
    }

    @Test("Encoded JSON has expected structure")
    func encodedJSONStructure() throws {
        let config = WorkflowConfiguration(ci: true, release: false, docs: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["ci"] as? Bool == true)
        #expect(json?["release"] as? Bool == false)
        #expect(json?["docs"] as? Bool == true)
    }

    // MARK: - Equatable Conformance

    @Test("Equal configurations are equal")
    func equalConfigsAreEqual() {
        let config1 = WorkflowConfiguration(ci: true, release: true, docs: false)
        let config2 = WorkflowConfiguration(ci: true, release: true, docs: false)

        #expect(config1 == config2)
    }

    @Test("Different CI values are not equal")
    func differentCINotEqual() {
        let config1 = WorkflowConfiguration(ci: true, release: true, docs: true)
        let config2 = WorkflowConfiguration(ci: false, release: true, docs: true)

        #expect(config1 != config2)
    }

    @Test("Different release values are not equal")
    func differentReleaseNotEqual() {
        let config1 = WorkflowConfiguration(ci: true, release: true, docs: true)
        let config2 = WorkflowConfiguration(ci: true, release: false, docs: true)

        #expect(config1 != config2)
    }

    @Test("Different docs values are not equal")
    func differentDocsNotEqual() {
        let config1 = WorkflowConfiguration(ci: true, release: true, docs: true)
        let config2 = WorkflowConfiguration(ci: true, release: true, docs: false)

        #expect(config1 != config2)
    }

    @Test("Default configs are all equal")
    func defaultConfigsEqual() {
        let config1 = WorkflowConfiguration()
        let config2 = WorkflowConfiguration()

        #expect(config1 == config2)
    }
}

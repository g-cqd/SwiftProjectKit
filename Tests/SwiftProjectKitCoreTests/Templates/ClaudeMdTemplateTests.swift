// ClaudeMdTemplateTests.swift
// Tests for CLAUDE.md template validity and content structure.
//
// ## Test Goals
// - Verify the template is valid Markdown with proper structure
// - Ensure all required sections are present in correct order
// - Validate code examples are properly formatted
// - Confirm Swift best practices are documented
//
// ## Why These Tests Matter
// CLAUDE.md provides AI assistants with project guidelines. Invalid or
// incomplete templates lead to poor AI-assisted code quality.

import Foundation
import Testing

@testable import SwiftProjectKitCore

@Suite("CLAUDE.md Template Tests")
struct ClaudeMdTemplateTests {
    // MARK: - Basic Validity

    @Test("Template is non-empty")
    func templateNotEmpty() {
        let template = DefaultConfigs.claudeMd
        #expect(!template.isEmpty, "CLAUDE.md template must not be empty")
    }

    @Test("Template has substantial content")
    func templateHasSubstantialContent() {
        let template = DefaultConfigs.claudeMd
        #expect(template.count > 1000, "Template should have substantial guidelines")
    }

    // MARK: - Required Top-Level Sections

    @Test("Contains main title heading")
    func containsMainTitle() {
        let template = DefaultConfigs.claudeMd

        #expect(
            template.contains("# Elite Software Engineer Guidelines"),
            "Must have main title heading",
        )
    }

    @Test("Contains Core Mandates section")
    func containsCoreMandates() {
        let template = DefaultConfigs.claudeMd

        #expect(
            template.contains("## Core Mandates"),
            "Must have Core Mandates section",
        )
    }

    @Test("Contains Swift Best Practices section")
    func containsSwiftBestPractices() {
        let template = DefaultConfigs.claudeMd

        #expect(
            template.contains("## Swift Best Practices"),
            "Must have Swift Best Practices section",
        )
    }

    @Test("Contains Implementation Guidelines section")
    func containsImplementationGuidelines() {
        let template = DefaultConfigs.claudeMd

        #expect(
            template.contains("## Implementation Guidelines"),
            "Must have Implementation Guidelines section",
        )
    }

    @Test("Contains Forbidden Patterns section")
    func containsForbiddenPatterns() {
        let template = DefaultConfigs.claudeMd

        #expect(
            template.contains("## Forbidden Patterns"),
            "Must have Forbidden Patterns section",
        )
    }

    // MARK: - Section Order

    @Test("Sections appear in correct order")
    func sectionsInCorrectOrder() {
        let template = DefaultConfigs.claudeMd

        let coreIndex = template.range(of: "## Core Mandates")?.lowerBound
        let swiftIndex = template.range(of: "## Swift Best Practices")?.lowerBound
        let implIndex = template.range(of: "## Implementation Guidelines")?.lowerBound
        let forbiddenIndex = template.range(of: "## Forbidden Patterns")?.lowerBound

        guard let core = coreIndex,
            let swift = swiftIndex,
            let impl = implIndex,
            let forbidden = forbiddenIndex
        else {
            Issue.record("Missing required sections")
            return
        }

        #expect(core < swift, "Core Mandates should come before Swift Best Practices")
        #expect(swift < impl, "Swift Best Practices should come before Implementation Guidelines")
        #expect(impl < forbidden, "Implementation Guidelines should come before Forbidden Patterns")
    }

    // MARK: - SOLID Principles

    @Test("Documents all SOLID principles")
    func documentsSOLIDPrinciples() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("SOLID"), "Must mention SOLID")
        #expect(template.contains("Single Responsibility"), "Must document Single Responsibility")
        #expect(template.contains("Open/Closed"), "Must document Open/Closed")
        #expect(template.contains("Liskov Substitution"), "Must document Liskov Substitution")
        #expect(template.contains("Interface Segregation"), "Must document Interface Segregation")
        #expect(template.contains("Dependency Inversion"), "Must document Dependency Inversion")
    }

    // MARK: - Core Principles

    @Test("Documents DRY principle")
    func documentsDRY() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("DRY"), "Must document DRY principle")
        #expect(
            template.contains("Don't Repeat Yourself"),
            "Must explain DRY acronym",
        )
    }

    @Test("Documents KISS principle")
    func documentsKISS() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("KISS"), "Must document KISS principle")
    }

    // MARK: - Swift 6 / Modern Swift

    @Test("Documents Swift 6 concurrency")
    func documentsSwift6Concurrency() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("Swift 6"), "Must mention Swift 6")
        #expect(template.contains("Strict Concurrency"), "Must mention Strict Concurrency")
        #expect(template.contains("Sendable"), "Must document Sendable")
        #expect(template.contains("actor"), "Must document actors")
    }

    @Test("Documents MainActor usage")
    func documentsMainActor() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("MainActor"), "Must document MainActor")
    }

    // MARK: - Forbidden Patterns

    @Test("Forbids DispatchQueue")
    func forbidsDispatchQueue() {
        let template = DefaultConfigs.claudeMd

        #expect(
            template.contains("DispatchQueue"),
            "Must mention DispatchQueue in forbidden patterns",
        )
        #expect(
            template.contains("NEVER") && template.contains("DispatchQueue"),
            "Should strongly discourage DispatchQueue",
        )
    }

    @Test("Forbids force unwrapping")
    func forbidsForceUnwrapping() {
        let template = DefaultConfigs.claudeMd

        #expect(
            template.contains("try!") || template.contains("force unwrap"),
            "Must forbid force unwrapping",
        )
    }

    @Test("Forbids force casting")
    func forbidsForceCasting() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("as!"), "Must forbid force casting (as!)")
    }

    // MARK: - Code Examples

    @Test("Contains Swift code examples")
    func containsCodeExamples() {
        let template = DefaultConfigs.claudeMd

        #expect(
            template.contains("```swift"),
            "Must contain Swift code examples",
        )
    }

    @Test("Shows both good and bad examples")
    func showsGoodAndBadExamples() {
        let template = DefaultConfigs.claudeMd

        let hasGood = template.contains("GOOD") || template.contains("### GOOD")
        let hasBad = template.contains("BAD") || template.contains("### BAD")

        #expect(hasGood, "Should show good examples")
        #expect(hasBad, "Should show bad examples to avoid")
    }

    // MARK: - Value Types

    @Test("Promotes value types")
    func promotesValueTypes() {
        let template = DefaultConfigs.claudeMd

        #expect(template.contains("struct"), "Must discuss structs")
        #expect(
            template.contains("Value Type") || template.contains("value types"),
            "Must promote value types",
        )
    }

    // MARK: - Markdown Validity

    @Test("All code blocks are closed")
    func allCodeBlocksClosed() {
        let template = DefaultConfigs.claudeMd

        let openCount = template.components(separatedBy: "```").count - 1

        #expect(
            openCount.isMultiple(of: 2),
            "All code blocks must be properly closed (found \(openCount) markers)",
        )
    }
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftProjectKit open source project
//
// Copyright (c) 2024 g-cqd and the SwiftProjectKit project authors
// Licensed under MIT License
//
//===----------------------------------------------------------------------===//

import Foundation
import Testing

@testable import SwiftProjectKitCore

@Suite("HooksConfiguration Tests")
struct HooksConfigurationTests {

    // MARK: - Default Configuration

    @Test("Default configuration values")
    func defaultConfiguration() {
        let config = HooksConfiguration.default

        #expect(config.fixMode == .safe)
        #expect(config.restageFixed == true)
        #expect(config.failFast == false)
    }

    // MARK: - HookStageConfig Tests

    @Test("Default pre-commit configuration")
    func defaultPreCommit() {
        let config = HookStageConfig.defaultPreCommit

        #expect(config.enabled == true)
        #expect(config.scope == .staged)
        #expect(config.parallel == true)
        #expect(config.tasks.contains("format"))
        #expect(config.tasks.contains("build"))
    }

    @Test("Default pre-push configuration")
    func defaultPrePush() {
        let config = HookStageConfig.defaultPrePush

        #expect(config.enabled == true)
        #expect(config.scope == .changed)
        #expect(config.baseBranch == "main")
        #expect(config.tasks.contains("test"))
    }

    @Test("Default CI configuration")
    func defaultCI() {
        let config = HookStageConfig.defaultCI

        #expect(config.enabled == true)
        #expect(config.scope == .all)
        #expect(config.tasks.contains("build"))
        #expect(config.tasks.contains("test"))
    }

    // MARK: - TaskConfig Tests

    @Test("TaskConfig default values")
    func taskConfigDefaults() {
        let config = TaskConfig()

        #expect(config.enabled == true)
        #expect(config.blocking == true)
        #expect(config.fixSafety == nil)
        #expect(config.paths == nil)
        #expect(config.excludePaths == nil)
    }

    @Test("TaskConfig with custom values")
    func taskConfigCustom() {
        let config = TaskConfig(
            enabled: false,
            blocking: false,
            fixSafety: .cautious,
            paths: ["Sources/"],
            excludePaths: ["**/Fixtures/**"]
        )

        #expect(config.enabled == false)
        #expect(config.blocking == false)
        #expect(config.fixSafety == .cautious)
        #expect(config.paths?.count == 1)
        #expect(config.excludePaths?.count == 1)
    }

    // MARK: - AnyCodable Tests

    @Test("AnyCodable with bool")
    func anyCodableBool() throws {
        let value = AnyCodable(true)
        #expect(value.value as? Bool == true)
    }

    @Test("AnyCodable with int")
    func anyCodableInt() throws {
        let value = AnyCodable(42)
        #expect(value.value as? Int == 42)
    }

    @Test("AnyCodable with string")
    func anyCodableString() throws {
        let value = AnyCodable("test")
        #expect(value.value as? String == "test")
    }

    @Test("AnyCodable equality")
    func anyCodableEquality() {
        let a = AnyCodable("test")
        let b = AnyCodable("test")
        #expect(a == b)
    }

    // MARK: - Codable Tests

    @Test("HooksConfiguration encodes and decodes")
    func configurationCodable() throws {
        let original = HooksConfiguration(
            fixMode: .cautious,
            restageFixed: false,
            failFast: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HooksConfiguration.self, from: data)

        #expect(decoded.fixMode == .cautious)
        #expect(decoded.restageFixed == false)
        #expect(decoded.failFast == true)
    }

    @Test("HookStageConfig encodes and decodes")
    func stageConfigCodable() throws {
        let original = HookStageConfig(
            enabled: true,
            scope: .changed,
            baseBranch: "develop",
            parallel: false,
            tasks: ["format", "lint"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HookStageConfig.self, from: data)

        #expect(decoded.enabled == true)
        #expect(decoded.scope == .changed)
        #expect(decoded.baseBranch == "develop")
        #expect(decoded.parallel == false)
        #expect(decoded.tasks == ["format", "lint"])
    }
}

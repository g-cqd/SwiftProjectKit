// MARK: - Trailing Comma Test Fixtures
// Tests: SwiftFormat `trailingCommas` vs SwiftLint `trailing_comma`
//
// Run: swiftformat --lint TrailingCommaTests.swift
// Run: swiftlint lint TrailingCommaTests.swift

import Foundation

// MARK: - Test Case 1: Multiline Array (Should Have Trailing Comma)

enum TrailingCommaTests {

    // GOOD: Trailing comma in multiline array (better git diffs)
    static let colorsGood = [
        "red",
        "green",
        "blue",
    ]

    // BAD: Missing trailing comma (worse git diffs when adding items)
    static let colorsBad = [
        "red",
        "green",
        "blue"
    ]

    // MARK: - Test Case 2: Single-Line Array (No Trailing Comma)

    // GOOD: No trailing comma in single-line array
    static let singleLineGood = ["a", "b", "c"]

    // BAD: Trailing comma in single-line (looks odd)
    static let singleLineBad = ["a", "b", "c",]

    // MARK: - Test Case 3: Multiline Dictionary

    // GOOD: Trailing comma in multiline dictionary
    static let configGood: [String: Any] = [
        "key1": "value1",
        "key2": "value2",
        "key3": "value3",
    ]

    // BAD: Missing trailing comma
    static let configBad: [String: Any] = [
        "key1": "value1",
        "key2": "value2",
        "key3": "value3"
    ]

    // MARK: - Test Case 4: Function Parameters (Multiline)

    // GOOD: Trailing comma in multiline parameters (Swift 5.9+)
    static func createUserGood(
        name: String,
        email: String,
        age: Int,
    ) -> String {
        "\(name) - \(email) - \(age)"
    }

    // BAD: No trailing comma in multiline parameters
    static func createUserBad(
        name: String,
        email: String,
        age: Int
    ) -> String {
        "\(name) - \(email) - \(age)"
    }

    // MARK: - Test Case 5: Enum Cases

    enum Status {
        case active
        case inactive
        case pending
    }

    // MARK: - Test Case 6: Closure with Capture List

    static let closureExample = { [weak self, count = 5,] in
        print("Captured")
    }
}

// MARK: - Expected Results
//
// SwiftFormat (--commas always):
// - Will ADD trailing commas to colorsBad, configBad, createUserBad
// - Will REMOVE trailing comma from singleLineBad (only on single lines with specific config)
//
// SwiftLint (trailing_comma disabled):
// - Will NOT warn about any of these (rule is disabled)
//
// If SwiftLint trailing_comma were enabled with mandatory_comma: true:
// - Would WARN on colorsBad, configBad (missing comma)
//
// RECOMMENDATION: Keep SwiftLint trailing_comma disabled, let SwiftFormat handle it

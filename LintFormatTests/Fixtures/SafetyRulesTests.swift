// MARK: - Safety Rules Test Fixtures (SwiftLint Only)
// Tests rules that ONLY exist in SwiftLint (no SwiftFormat equivalent)
//
// Run: swiftlint lint SafetyRulesTests.swift

import Foundation

// MARK: - Test Case 1: Force Unwrapping (force_unwrapping)

enum ForceUnwrapTests {

    // BAD: Force unwrapping - DANGEROUS
    static func badExample() -> String {
        let optional: String? = "value"
        return optional! // swiftlint:disable:this force_unwrapping
    }

    // GOOD: Safe unwrapping with guard
    static func goodExample() -> String {
        let optional: String? = "value"
        guard let value = optional else {
            return "default"
        }
        return value
    }

    // GOOD: Using nil coalescing
    static func betterExample() -> String {
        let optional: String? = "value"
        return optional ?? "default"
    }
}

// MARK: - Test Case 2: Implicitly Unwrapped Optionals (implicitly_unwrapped_optional)

final class ImplicitUnwrapTests {

    // BAD: Implicitly unwrapped optional
    // swiftlint:disable:next implicitly_unwrapped_optional
    var badProperty: String!

    // GOOD: Regular optional
    var goodProperty: String?

    // GOOD: Non-optional with default
    var betterProperty: String = ""

    // EXCEPTION: IBOutlets (usually acceptable)
    // @IBOutlet weak var button: UIButton!
}

// MARK: - Test Case 3: Force Cast (force_cast)

enum ForceCastTests {

    // BAD: Force cast - can crash
    static func badExample(_ any: Any) -> String {
        // swiftlint:disable:next force_cast
        return any as! String
    }

    // GOOD: Safe cast with guard
    static func goodExample(_ any: Any) -> String {
        guard let string = any as? String else {
            return "default"
        }
        return string
    }
}

// MARK: - Test Case 4: Force Try (force_try)

enum ForceTryTests {

    // BAD: Force try - can crash
    static func badExample() -> Data {
        // swiftlint:disable:next force_try
        return try! Data(contentsOf: URL(fileURLWithPath: "/tmp/file"))
    }

    // GOOD: Proper error handling
    static func goodExample() -> Data? {
        do {
            return try Data(contentsOf: URL(fileURLWithPath: "/tmp/file"))
        } catch {
            print("Error: \(error)")
            return nil
        }
    }

    // GOOD: With typed throws (Swift 6)
    enum FileError: Error {
        case notFound
    }

    static func typedExample() throws(FileError) -> Data {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/file")) else {
            throw .notFound
        }
        return data
    }
}

// MARK: - Test Case 5: Cyclomatic Complexity (cyclomatic_complexity)

enum ComplexityTests {

    // BAD: High cyclomatic complexity (warning at 15, error at 25)
    // swiftlint:disable:next cyclomatic_complexity
    static func tooComplex(value: Int) -> String {
        if value == 1 { return "one" }
        else if value == 2 { return "two" }
        else if value == 3 { return "three" }
        else if value == 4 { return "four" }
        else if value == 5 { return "five" }
        else if value == 6 { return "six" }
        else if value == 7 { return "seven" }
        else if value == 8 { return "eight" }
        else if value == 9 { return "nine" }
        else if value == 10 { return "ten" }
        else if value == 11 { return "eleven" }
        else if value == 12 { return "twelve" }
        else if value == 13 { return "thirteen" }
        else if value == 14 { return "fourteen" }
        else if value == 15 { return "fifteen" }
        else if value == 16 { return "sixteen" }
        else { return "other" }
    }

    // GOOD: Use switch or dictionary lookup
    static func lessComplex(value: Int) -> String {
        switch value {
        case 1: "one"
        case 2: "two"
        case 3: "three"
        default: "other"
        }
    }
}

// MARK: - Test Case 6: Function Body Length (function_body_length)

// Config: warning at 50 lines, error at 100 lines
// Long functions should be broken into smaller, focused functions

// MARK: - Test Case 7: Unowned Variable Capture (unowned_variable_capture)

final class UnownedCaptureTests {

    var handler: (() -> Void)?

    // BAD: unowned can cause crashes if self is deallocated
    func badExample() {
        // swiftlint:disable:next unowned_variable_capture
        handler = { [unowned self] in
            print(self)
        }
    }

    // GOOD: weak is safer
    func goodExample() {
        handler = { [weak self] in
            guard let self else { return }
            print(self)
        }
    }
}

// MARK: - Expected Behavior
//
// These rules are SwiftLint-only and CRITICAL for code safety.
// SwiftFormat cannot detect these issues - they are semantic, not stylistic.
//
// RECOMMENDATION:
// 1. Keep ALL safety rules enabled in SwiftLint
// 2. Set force_unwrapping to ERROR level, not WARNING
// 3. Keep cyclomatic_complexity thresholds (15/25) reasonable
// 4. Keep function_body_length thresholds (50/100) to encourage small functions

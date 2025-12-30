// MARK: - Code Quality Test Fixtures
// Tests rules for code elegance, readability, and best practices
//
// Run: xcrun swift-format lint --strict CodeQualityTests.swift

import Foundation

// MARK: - Test Case 1: Empty Collection Checks

enum EmptyCollectionTests {

    // BAD: Using count == 0
    static func badCountCheck(_ array: [Int]) -> Bool {
        array.count == 0
    }

    // GOOD: Using isEmpty
    static func goodIsEmptyCheck(_ array: [Int]) -> Bool {
        array.isEmpty
    }

    // BAD: Using count > 0
    static func badNotEmptyCheck(_ array: [Int]) -> Bool {
        array.count > 0
    }

    // GOOD: Using !isEmpty
    static func goodNotEmptyCheck(_ array: [Int]) -> Bool {
        !array.isEmpty
    }
}

// MARK: - Test Case 2: First/Last Where

enum FirstLastWhereTests {

    // BAD: filter().first
    static func badFilterFirst(_ numbers: [Int]) -> Int? {
        numbers.filter { $0 > 5 }.first
    }

    // GOOD: first(where:)
    static func goodFirstWhere(_ numbers: [Int]) -> Int? {
        numbers.first { $0 > 5 }
    }

    // BAD: filter().last
    static func badFilterLast(_ numbers: [Int]) -> Int? {
        numbers.filter { $0 > 5 }.last
    }

    // GOOD: last(where:)
    static func goodLastWhere(_ numbers: [Int]) -> Int? {
        numbers.last { $0 > 5 }
    }
}

// MARK: - Test Case 3: Reduce Into

enum ReduceIntoTests {

    // BAD: reduce with copy
    static func badReduce(_ strings: [String]) -> [String: Int] {
        strings.reduce([:]) { result, string in
            var dict = result
            dict[string] = string.count
            return dict
        }
    }

    // GOOD: reduce(into:) - more efficient
    static func goodReduceInto(_ strings: [String]) -> [String: Int] {
        strings.reduce(into: [:]) { result, string in
            result[string] = string.count
        }
    }
}

// MARK: - Test Case 4: Toggle Bool

enum ToggleBoolTests {

    static var flag = false

    // BAD: Manual negation
    static func badToggle() {
        flag = !flag
    }

    // GOOD: Using toggle()
    static func goodToggle() {
        flag.toggle()
    }
}

// MARK: - Test Case 5: Sorted First/Last

enum SortedFirstLastTests {

    // BAD: sorted().first
    static func badSortedFirst(_ numbers: [Int]) -> Int? {
        numbers.sorted().first
    }

    // GOOD: min()
    static func goodMin(_ numbers: [Int]) -> Int? {
        numbers.min()
    }

    // BAD: sorted().last
    static func badSortedLast(_ numbers: [Int]) -> Int? {
        numbers.sorted().last
    }

    // GOOD: max()
    static func goodMax(_ numbers: [Int]) -> Int? {
        numbers.max()
    }
}

// MARK: - Test Case 6: Redundant Nil Coalescing

enum RedundantNilCoalescingTests {

    // BAD: Nil coalescing with nil
    static func badNilCoalescing(_ value: String?) -> String? {
        value ?? nil
    }

    // GOOD: Just use the optional
    static func goodOptional(_ value: String?) -> String? {
        value
    }
}

// MARK: - Test Case 7: Contains Over Filter

enum ContainsOverFilterTests {

    // BAD: !filter().isEmpty
    static func badFilterIsEmpty(_ numbers: [Int]) -> Bool {
        !numbers.filter { $0 > 5 }.isEmpty
    }

    // GOOD: contains(where:)
    static func goodContains(_ numbers: [Int]) -> Bool {
        numbers.contains { $0 > 5 }
    }

    // BAD: filter().count > 0
    static func badFilterCount(_ numbers: [Int]) -> Bool {
        numbers.filter { $0 > 5 }.count > 0
    }
}

// MARK: - Test Case 8: Yoda Condition

enum YodaConditionTests {

    // BAD: Yoda condition (constant on left)
    static func badYoda(_ value: Int) -> Bool {
        5 == value
    }

    // GOOD: Variable on left
    static func goodCondition(_ value: Int) -> Bool {
        value == 5
    }
}

// MARK: - Test Case 9: Discouraged Optional Boolean

enum OptionalBoolTests {

    // BAD: Optional Bool is confusing (true, false, or nil?)
    static func badOptionalBool() -> Bool? {
        nil
    }

    // GOOD: Use an enum for three-state logic
    enum TriState {
        case yes
        case no
        case unknown
    }

    static func goodTriState() -> TriState {
        .unknown
    }
}

// MARK: - Expected Behavior
//
// swift-format focuses on formatting consistency.
// For semantic code quality rules (like isEmpty, first(where:), etc.),
// consider using additional static analysis tools or code review.
//
// RECOMMENDATION:
// 1. Use swift-format for consistent formatting
// 2. Enable UseEarlyExits rule for guard statements
// 3. Apply code quality improvements during code review

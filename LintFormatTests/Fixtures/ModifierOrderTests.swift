// MARK: - Modifier Order Test Fixtures
// Tests: swift-format modifier ordering
//
// Run: xcrun swift-format lint --strict ModifierOrderTests.swift

import Foundation

// MARK: - Test Case 1: Correct Modifier Order

// GOOD: Correct order per swift-format defaults
// Order: override, access control, @attributes, static/class, mutating, final
final class CorrectOrderExample {

    // Correct: public static let
    public static let sharedInstance = CorrectOrderExample()

    // Correct: private final func
    private final func process() {}

    // Correct: override public func
    public func overriddenMethod() {}

    // Correct: @MainActor private var
    @MainActor private var state: Int = 0
}

// MARK: - Test Case 2: Incorrect Modifier Order (Will Be Fixed)

// BAD: Wrong order - static before access control
final class IncorrectOrderExample {

    // BAD: static public (should be public static)
    static public let badOrder1 = "wrong"

    // BAD: final private (should be private final)
    final private func badOrder2() {}
}

// MARK: - Test Case 3: Complex Modifier Scenarios

actor ComplexModifierExample {

    // Correct: nonisolated public func
    nonisolated public func isolatedMethod() {}

    // Multiple attributes
    @MainActor @available(iOS 15, *)
    public func attributedMethod() {}
}

// MARK: - Test Case 4: Protocol Conformance Modifiers

protocol ModifierTestProtocol {
    func requiredMethod()
}

class ConformingClass: ModifierTestProtocol {
    // Correct order for protocol implementation
    internal func requiredMethod() {}
}

// MARK: - Expected Behavior
//
// swift-format will:
// - REORDER badOrder1 to: `public static let`
// - REORDER badOrder2 to: `private final func`
//
// Default Order:
// 1. override
// 2. Access control (private, fileprivate, internal, public, open)
// 3. @attributes (@MainActor, @available, etc.)
// 4. static / class
// 5. final
// 6. mutating / nonmutating
// 7. lazy
// 8. var / let / func / etc.
//
// RECOMMENDATION: Let swift-format handle modifier ordering automatically.

enum ModifierOrderTests {
    static func runTests() {
        print("Modifier order tests")
    }
}

// MARK: - Import Sorting Test Fixtures
// Tests: SwiftFormat `sortedImports` vs SwiftLint `sorted_imports`
//
// Run: swiftformat --lint ImportSortingTests.swift
// Run: swiftlint lint ImportSortingTests.swift

// MARK: - Test Case 1: Unsorted Imports (BAD)

// BAD: Imports not alphabetically sorted
// import Foundation
// import UIKit
// import Combine
// import SwiftUI
// @testable import MyModule

// MARK: - Test Case 2: Alphabetically Sorted (GOOD for SwiftLint)

// GOOD for SwiftLint (pure alphabetical)
// import Combine
// import Foundation
// import SwiftUI
// import UIKit
// @testable import MyModule

// MARK: - Test Case 3: Grouped Imports (GOOD for SwiftFormat with grouping)

// GOOD for SwiftFormat (--importgrouping testable-last)
// Groups: System frameworks, then @testable imports last
import Combine
import Foundation
import SwiftUI
import UIKit

@testable import SwiftProjectKit

// MARK: - Test Case 4: Case Sensitivity Issue

// SwiftLint sorts case-sensitively by default (A before a)
// This can cause issues with imports like:
// import ACL
// import AVFoundation
// import Accessibility

// MARK: - Potential Conflict Analysis
//
// SwiftFormat `--importgrouping testable-last`:
// 1. Standard imports (alphabetical)
// 2. @testable imports (alphabetical, at end)
//
// SwiftLint `sorted_imports`:
// - Expects ALL imports in one alphabetical block
// - Does NOT understand grouping
// - May warn about @testable imports being "out of order"
//
// RECOMMENDATION:
// Option A: Disable `sorted_imports` in SwiftLint (let SwiftFormat handle it)
// Option B: Use `--importgrouping alpha` in SwiftFormat (no grouping)
//
// Current Config Analysis:
// - SwiftFormat: `--importgrouping testable-last` (groups imports)
// - SwiftLint: `sorted_imports` in opt_in_rules (enabled)
//
// POTENTIAL CONFLICT: SwiftLint may warn about @testable imports
// being after regular imports even though SwiftFormat intentionally
// places them there.

enum ImportSortingTests {
    static func example() {
        // This file exists to test import sorting behavior
        print("Import sorting test")
    }
}

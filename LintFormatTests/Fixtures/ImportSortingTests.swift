// MARK: - Import Sorting Test Fixtures
// Tests: swift-format `OrderedImports` rule
//
// Run: xcrun swift-format lint --strict ImportSortingTests.swift

// MARK: - Test Case 1: Unsorted Imports (BAD)

// BAD: Imports not alphabetically sorted
// import Foundation
// import UIKit
// import Combine
// import SwiftUI
// @testable import MyModule

// MARK: - Test Case 2: Alphabetically Sorted (GOOD)

// GOOD: Pure alphabetical sorting
// import Combine
// import Foundation
// import SwiftUI
// import UIKit
// @testable import MyModule

// MARK: - Test Case 3: Grouped Imports (GOOD for swift-format)

// GOOD for swift-format (OrderedImports rule)
// Groups: System frameworks alphabetically, then @testable imports last
import Combine
import Foundation
import SwiftUI
import UIKit

@testable import SwiftProjectKit

// MARK: - Test Case 4: Case Sensitivity

// swift-format handles case-sensitive sorting correctly:
// import ACL
// import AVFoundation
// import Accessibility

// MARK: - Configuration
//
// swift-format `OrderedImports` rule:
// - Sorts imports alphabetically
// - Handles @testable imports appropriately
//
// RECOMMENDATION:
// Enable OrderedImports in .swift-format configuration

enum ImportSortingTests {
    static func example() {
        // This file exists to test import sorting behavior
        print("Import sorting test")
    }
}

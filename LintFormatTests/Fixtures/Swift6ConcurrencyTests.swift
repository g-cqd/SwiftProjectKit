// MARK: - Swift 6 Concurrency Test Fixtures
// Tests for Swift 6+ strict concurrency compliance
//
// Run: swiftformat --lint Swift6ConcurrencyTests.swift
// Run: swiftlint lint Swift6ConcurrencyTests.swift

import Foundation

// MARK: - Test Case 1: Sendable Conformance

// GOOD: Proper Sendable conformance with immutable value type
struct UserData: Sendable {
    let id: UUID
    let name: String
    let email: String
}

// GOOD: Sendable actor (actors are implicitly Sendable)
actor DataStore {
    private var items: [String: UserData] = [:]

    func store(_ user: UserData) {
        items[user.id.uuidString] = user
    }

    func fetch(id: UUID) -> UserData? {
        items[id.uuidString]
    }
}

// BAD: @unchecked Sendable (avoid this)
// Custom rule `no_unchecked_sendable` should catch this
// swiftlint:disable:next custom_rules
final class UnsafeContainer: @unchecked Sendable {
    var mutableState: Int = 0  // This is NOT actually thread-safe!
}

// GOOD: Use actor instead
actor SafeContainer {
    var mutableState: Int = 0

    func increment() {
        mutableState += 1
    }
}

// MARK: - Test Case 2: MainActor Usage

// GOOD: ViewModel on MainActor
@MainActor
final class UserViewModel: ObservableObject {
    @Published private(set) var users: [UserData] = []
    @Published private(set) var isLoading = false

    private let dataStore: DataStore

    init(dataStore: DataStore = DataStore()) {
        self.dataStore = dataStore
    }

    func loadUser(id: UUID) async {
        isLoading = true
        defer { isLoading = false }

        if let user = await dataStore.fetch(id: id) {
            users.append(user)
        }
    }
}

// MARK: - Test Case 3: Task and Structured Concurrency

enum NetworkService {

    // GOOD: Async function with proper error handling
    static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
            (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw NetworkError.invalidResponse
        }

        return data
    }

    // GOOD: Task group for parallel operations
    static func fetchMultiple(urls: [URL]) async throws -> [Data] {
        try await withThrowingTaskGroup(of: Data.self) { group in
            for url in urls {
                group.addTask {
                    try await fetchData(from: url)
                }
            }

            var results: [Data] = []
            for try await data in group {
                results.append(data)
            }
            return results
        }
    }

    enum NetworkError: Error {
        case invalidResponse
        case connectionFailed
    }
}

// MARK: - Test Case 4: Avoiding DispatchQueue (Per CLAUDE.md)

// BAD: Using DispatchQueue (forbidden per project guidelines)
// enum LegacyExample {
//     static func badExample(completion: @escaping (String) -> Void) {
//         DispatchQueue.global().async {
//             // Work
//             DispatchQueue.main.async {
//                 completion("result")
//             }
//         }
//     }
// }

// GOOD: Using async/await
enum ModernExample {
    static func goodExample() async -> String {
        // Work happens on cooperative thread pool
        await Task.yield()  // Yield point if needed
        return "result"
    }
}

// MARK: - Test Case 5: Nonisolated Methods

actor ConfigurationStore {
    private var config: [String: String] = [:]

    // GOOD: nonisolated for synchronous access to immutable data
    nonisolated let identifier: UUID = UUID()

    // GOOD: nonisolated(unsafe) only when you REALLY know what you're doing
    // nonisolated(unsafe) var unsafeFlag: Bool = false

    func getValue(for key: String) -> String? {
        config[key]
    }

    func setValue(_ value: String, for key: String) {
        config[key] = value
    }
}

// MARK: - Test Case 6: AsyncSequence

// GOOD: Custom AsyncSequence
struct CountdownSequence: AsyncSequence {
    typealias Element = Int

    let start: Int

    struct AsyncIterator: AsyncIteratorProtocol {
        var current: Int

        mutating func next() async -> Int? {
            guard current > 0 else { return nil }
            defer { current -= 1 }
            try? await Task.sleep(for: .milliseconds(100))
            return current
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(current: start)
    }
}

// MARK: - Test Case 7: Typed Throws (Swift 6)

enum ValidationError: Error {
    case empty
    case tooShort
    case invalidFormat
}

// GOOD: Typed throws for precise error handling
func validateUsername(_ username: String) throws(ValidationError) -> String {
    guard !username.isEmpty else {
        throw .empty
    }

    guard username.count >= 3 else {
        throw .tooShort
    }

    guard username.allSatisfy(\.isLetter) else {
        throw .invalidFormat
    }

    return username.lowercased()
}

// MARK: - Expected Behavior
//
// SwiftLint custom rules should catch:
// - @unchecked Sendable usage (no_unchecked_sendable)
// - DispatchQueue usage (could add custom rule)
//
// SwiftFormat will:
// - Organize declarations within actors
// - Format async/await syntax consistently
//
// RECOMMENDATION:
// 1. Enable strict concurrency checking in build settings
// 2. Use actors for shared mutable state
// 3. Prefer async/await over callbacks
// 4. Use typed throws for precise error handling
// 5. Add custom SwiftLint rules for concurrency anti-patterns

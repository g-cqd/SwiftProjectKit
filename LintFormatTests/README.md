# swift-format Test Fixtures

Test fixtures for validating apple/swift-format rules and configurations.

## Directory Structure

```
LintFormatTests/
├── README.md                       # This file
├── Fixtures/                       # Test Swift files
│   ├── TrailingCommaTests.swift    # Trailing comma scenarios
│   ├── SafetyRulesTests.swift      # Safety rule scenarios (force unwrap, etc.)
│   ├── CodeQualityTests.swift      # Code quality scenarios
│   └── Swift6ConcurrencyTests.swift # Swift 6 concurrency patterns
└── Scripts/
    └── run_tests.sh                # Run format checks
```

## Running Format Checks

```bash
# Check formatting on fixtures
xcrun swift-format lint --strict --recursive LintFormatTests/Fixtures/

# Format fixtures
xcrun swift-format format --in-place --recursive LintFormatTests/Fixtures/
```

## Fixture Files

Each fixture demonstrates specific rules:

| File | Tests |
|------|-------|
| `TrailingCommaTests.swift` | `multiElementCollectionTrailingCommas` |
| `SafetyRulesTests.swift` | `NeverForceUnwrap`, `NeverUseForceTry`, `NeverUseImplicitlyUnwrappedOptionals` |
| `CodeQualityTests.swift` | `UseEarlyExits`, `OrderedImports`, etc. |
| `Swift6ConcurrencyTests.swift` | Actors, Sendable, async/await patterns |

## Configuration

The project uses `.swift-format` (JSON) at the repository root. Key rules enabled:

- `NeverForceUnwrap` - Prevents force unwrapping
- `NeverUseForceTry` - Prevents force try
- `NeverUseImplicitlyUnwrappedOptionals` - Prevents IUOs
- `OrderedImports` - Sorts imports alphabetically
- `UseEarlyExits` - Encourages guard statements

## Note on Test Fixtures

Some fixtures intentionally contain code that violates rules to test that the linter catches them.
These files use `// swift-format-ignore-file` to prevent CI failures.

## References

- [apple/swift-format GitHub](https://github.com/swiftlang/swift-format)
- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)

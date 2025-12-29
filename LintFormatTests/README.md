# SwiftFormat & SwiftLint Test Suite

A comprehensive test suite for evaluating and refining SwiftFormat and SwiftLint configurations.

## Directory Structure

```
LintFormatTests/
├── README.md                    # This file
├── Configs/                     # Proposed configuration files
│   ├── proposed.swiftformat     # Refined SwiftFormat config
│   └── proposed.swiftlint.yml   # Refined SwiftLint config
├── Documentation/               # Analysis and planning documents
│   ├── CONFLICT_ANALYSIS.md     # Rule conflict analysis
│   └── REFINEMENT_PLAN.md       # Step-by-step improvement plan
├── Fixtures/                    # Test Swift files
│   ├── TrailingCommaTests.swift # Trailing comma scenarios
│   ├── ImportSortingTests.swift # Import sorting scenarios
│   ├── ModifierOrderTests.swift # Modifier order scenarios
│   ├── SafetyRulesTests.swift   # Safety rule scenarios
│   ├── CodeQualityTests.swift   # Code quality scenarios
│   └── Swift6ConcurrencyTests.swift # Swift 6 concurrency
└── Scripts/                     # Test automation
    └── run_tests.sh             # Run all tests
```

## Quick Start

### 1. Run Tests

```bash
# Run both tools against all fixtures
./LintFormatTests/Scripts/run_tests.sh

# Or manually:
swiftformat --lint LintFormatTests/Fixtures/
swiftlint lint LintFormatTests/Fixtures/
```

### 2. Review Conflicts

See [Documentation/CONFLICT_ANALYSIS.md](Documentation/CONFLICT_ANALYSIS.md) for:
- Known rule conflicts
- Overlapping rules
- SwiftLint-only rules
- SwiftFormat-only rules

### 3. Apply Proposed Configs

```bash
# Backup current configs
cp .swiftformat .swiftformat.backup
cp .swiftlint.yml .swiftlint.yml.backup

# Apply proposed configs
cp LintFormatTests/Configs/proposed.swiftformat .swiftformat
cp LintFormatTests/Configs/proposed.swiftlint.yml .swiftlint.yml

# Test on codebase
swiftformat --lint Sources/
swiftlint lint Sources/
```

## Key Findings

### Resolved Conflicts

| Conflict | Resolution |
|----------|------------|
| Trailing comma | SwiftFormat handles it, SwiftLint disabled |
| Import sorting | SwiftFormat handles grouping, SwiftLint disabled |
| Modifier order | Both aligned since SwiftFormat 0.44.8 |
| Brace wrapping | SwiftFormat's `wrapMultilineStatementBraces` disabled |

### Recommended Workflow

```
Write Code → Build (SwiftLint warnings) → Pre-commit (SwiftFormat) → CI (Both)
```

1. **During development**: SwiftLint shows warnings in Xcode
2. **On commit**: SwiftFormat auto-fixes formatting
3. **On CI**: Both tools validate (SwiftFormat `--lint`, SwiftLint)

## Fixture Files

Each fixture demonstrates specific rules:

| File | Tests |
|------|-------|
| `TrailingCommaTests.swift` | `--commas always` vs `trailing_comma` |
| `ImportSortingTests.swift` | `--importgrouping` vs `sorted_imports` |
| `ModifierOrderTests.swift` | `modifierOrder` vs `modifier_order` |
| `SafetyRulesTests.swift` | `force_unwrapping`, `force_cast`, etc. |
| `CodeQualityTests.swift` | `isEmpty`, `first_where`, `reduce_into`, etc. |
| `Swift6ConcurrencyTests.swift` | Actors, Sendable, async/await |

## References

- [SwiftFormat GitHub](https://github.com/nicklockwood/SwiftFormat)
- [SwiftLint GitHub](https://github.com/realm/SwiftLint)
- [Airbnb Swift Style Guide](https://github.com/airbnb/swift)
- [Google Swift Style Guide](https://google.github.io/swift/)

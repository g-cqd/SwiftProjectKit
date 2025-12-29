# SwiftFormat & SwiftLint Refinement Plan

## Overview

This document outlines a phased approach to refining the SwiftFormat and SwiftLint configurations for improved consistency, code quality, and elegance.

---

## Phase 1: Resolve Conflicts (Immediate)

### 1.1 Import Sorting Alignment

**Current Issue**: `sorted_imports` (SwiftLint) may conflict with `--importgrouping testable-last` (SwiftFormat).

**Action**: Disable `sorted_imports` in SwiftLint - let SwiftFormat handle import organization.

```yaml
# .swiftlint.yml - REMOVE from opt_in_rules
opt_in_rules:
  # - sorted_imports  # REMOVE: Let SwiftFormat handle this
```

**Rationale**: SwiftFormat's grouping (`testable-last`) is more sophisticated and widely adopted.

---

### 1.2 Trailing Comma Alignment

**Current Status**: Already aligned (SwiftFormat adds, SwiftLint rule disabled).

**Action**: No change needed. Document this as intentional.

---

### 1.3 Modifier Order Alignment

**Current Status**: Already aligned (both tools use same default order since SwiftFormat 0.44.8).

**Action**: No change needed.

---

## Phase 2: Add High-Value Rules (Short-term)

### 2.1 SwiftLint Additions

Add these high-value rules to `opt_in_rules`:

```yaml
opt_in_rules:
  # Existing rules...

  # ADD: Performance & Safety
  - convenience_type        # Use enum for namespacing (no instances)
  - discouraged_assert      # Prefer precondition/fatalError
  - file_types_order        # Consistent file organization
  - type_contents_order     # Consistent type organization

  # ADD: Modern Swift
  - prefer_self_in_static_references  # Swift 5.3+
  - shorthand_optional_binding        # Swift 5.7+ (if let x)
  - direct_return                     # Return directly when possible
  - superfluous_disable_command       # Clean up disable comments
```

### 2.2 SwiftFormat Additions

Consider enabling these SwiftFormat rules:

```
# .swiftformat - Consider adding
--enable docComments           # Format doc comments consistently
--enable extensionAccessControl # Consistent extension access control
--enable sortTypealiases       # Sort typealiases alphabetically
```

---

## Phase 3: Tighten Existing Rules (Medium-term)

### 3.1 Identifier Name Rules

**Current**: Disabled (`identifier_name`, `type_name`).

**Recommendation**: Enable with relaxed configuration:

```yaml
identifier_name:
  min_length:
    warning: 2      # Allow 'x', 'y', 'id'
    error: 1
  max_length:
    warning: 50
    error: 60
  excluded:
    - i
    - j
    - x
    - y
    - id
    - ok
    - to
    - T           # Generic type parameter
    - U
    - V

type_name:
  min_length:
    warning: 3
    error: 1
  max_length:
    warning: 50
    error: 60
```

**Rationale**: Naming rules improve readability but must allow common patterns.

---

### 3.2 Complexity Thresholds

**Current thresholds are reasonable**, but consider:

```yaml
cyclomatic_complexity:
  warning: 10     # Reduce from 15 (encourage simpler functions)
  error: 20       # Reduce from 25

function_body_length:
  warning: 40     # Reduce from 50
  error: 80       # Reduce from 100
```

**Rationale**: Lower thresholds encourage smaller, more focused functions.

---

## Phase 4: Add Custom Rules (Long-term)

### 4.1 Airbnb-Inspired Custom Rules

Consider adding these from the [Airbnb style guide](https://github.com/airbnb/swift):

```yaml
custom_rules:
  no_print_statements:
    name: "No Print Statements"
    regex: '^\s*(print|debugPrint|dump)\s*\('
    message: "Remove print statements before committing"
    severity: warning

  no_file_literal:
    name: "Prefer #fileID"
    regex: '#file(?!ID)\b'
    message: "Use #fileID instead of #file"
    severity: warning

  no_unchecked_sendable:
    name: "Avoid @unchecked Sendable"
    regex: '@unchecked\s+Sendable'
    message: "Use proper Sendable conformance or @preconcurrency import"
    severity: warning
```

---

## Phase 5: Workflow Optimization

### 5.1 Recommended Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                    Development Flow                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   [Write Code]                                              │
│        │                                                    │
│        ▼                                                    │
│   [Build in Xcode] ──► SwiftLint warnings appear inline     │
│        │                                                    │
│        ▼                                                    │
│   [Pre-commit Hook] ──► SwiftFormat auto-fixes              │
│        │                                                    │
│        ▼                                                    │
│   [CI/CD Pipeline]                                          │
│        ├──► SwiftFormat --lint (fail on formatting issues)  │
│        └──► SwiftLint (fail on errors, warn on warnings)    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 Tool Version Locking

Create a `Mintfile` for consistent tool versions:

```
realm/SwiftLint@0.57.0
nicklockwood/SwiftFormat@0.55.0
```

### 5.3 Git Hooks

Create `.githooks/pre-commit`:

```bash
#!/bin/bash
# Auto-format staged Swift files before commit

STAGED_FILES=$(git diff --cached --name-only --diff-filter=ACMR | grep "\.swift$")

if [ -n "$STAGED_FILES" ]; then
    echo "Running SwiftFormat on staged files..."
    echo "$STAGED_FILES" | xargs swiftformat --config .swiftformat

    # Re-stage formatted files
    echo "$STAGED_FILES" | xargs git add
fi
```

---

## Updated Configuration Files

### Proposed .swiftlint.yml

See: `../Configs/proposed.swiftlint.yml`

### Proposed .swiftformat

See: `../Configs/proposed.swiftformat`

---

## Metrics & Success Criteria

| Metric | Current | Target | Notes |
|--------|---------|--------|-------|
| Rule conflicts | ~2 | 0 | No conflicting rules |
| Lint warnings per file | Varies | < 5 avg | Low noise |
| Format violations after format | 0 | 0 | SwiftFormat is authoritative |
| CI build time impact | N/A | < 30s | Fast feedback |

---

## Implementation Timeline

| Phase | Priority | Effort |
|-------|----------|--------|
| Phase 1: Resolve Conflicts | High | Low |
| Phase 2: Add High-Value Rules | High | Low |
| Phase 3: Tighten Rules | Medium | Medium |
| Phase 4: Custom Rules | Medium | Medium |
| Phase 5: Workflow | Low | High |

---

## References

- [Airbnb Swift Style Guide](https://github.com/airbnb/swift)
- [Google Swift Style Guide](https://google.github.io/swift/)
- [SwiftFormat Rules Documentation](https://github.com/nicklockwood/SwiftFormat/blob/main/Rules.md)
- [SwiftLint Rule Reference](https://realm.github.io/SwiftLint/rule-directory.html)

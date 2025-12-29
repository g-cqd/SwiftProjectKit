# SwiftFormat & SwiftLint Conflict Analysis

## Executive Summary

This document analyzes rule conflicts between SwiftFormat and SwiftLint, informed by industry best practices from [Airbnb](https://github.com/airbnb/swift), [Google](https://google.github.io/swift/), and community research.

---

## 1. Identified Rule Conflicts

### 1.1 Trailing Comma Conflict (CRITICAL)

| Tool | Rule | Current Config | Behavior |
|------|------|----------------|----------|
| SwiftFormat | `trailingCommas` | `--commas always` | Adds trailing commas |
| SwiftLint | `trailing_comma` | `disabled_rules` | Disabled (no enforcement) |

**Status**: Currently safe - SwiftLint rule disabled.

**Best Practice**: Both tools should agree. Options:
- **Option A (Recommended)**: Enable trailing commas everywhere (modern Swift style, better diffs)
- **Option B**: Disable both rules

**Industry Reference**: [Airbnb enforces trailing commas](https://github.com/airbnb/swift) for cleaner git diffs.

---

### 1.2 Import Sorting Conflict (MODERATE)

| Tool | Rule | Current Config | Behavior |
|------|------|----------------|----------|
| SwiftFormat | `sortedImports` | Enabled (default) | Sorts imports alphabetically |
| SwiftLint | `sorted_imports` | `opt_in_rules` | Warns on unsorted imports |

**Status**: Potential conflict - SwiftLint may not recognize SwiftFormat's grouping.

**Issue**: SwiftFormat uses `--importgrouping testable-last` which groups imports, but SwiftLint's `sorted_imports` expects a single sorted block.

**Resolution**: Either:
1. Disable `sorted_imports` in SwiftLint (let SwiftFormat handle it)
2. Configure both to use the same sorting algorithm

---

### 1.3 Modifier Order Conflict (MODERATE)

| Tool | Rule | Current Config | Behavior |
|------|------|----------------|----------|
| SwiftFormat | `modifierOrder` | Enabled (default) | Reorders modifiers |
| SwiftLint | `modifier_order` | `opt_in_rules` | Warns on incorrect order |

**Status**: Aligned since SwiftFormat 0.44.8.

**Note**: SwiftFormat changed its default modifier order to match SwiftLint. Use `--specifierorder` if custom order needed.

---

### 1.4 Self Usage Conflict (LOW)

| Tool | Rule | Current Config | Behavior |
|------|------|----------------|----------|
| SwiftFormat | `redundantSelf` | `--self remove` | Removes explicit self |
| SwiftLint | N/A | No equivalent | N/A |

**Status**: No conflict - SwiftLint doesn't have an equivalent rule.

---

### 1.5 Wrap Multiline Statement Braces (LOW)

| Tool | Rule | Current Config | Behavior |
|------|------|----------------|----------|
| SwiftFormat | `wrapMultilineStatementBraces` | Disabled | Would wrap opening braces |
| SwiftLint | Various indentation rules | Multiple | May conflict |

**Status**: Safe - Already disabled in current config.

**Reference**: [Facebook iOS SDK](https://github.com/facebook/facebook-ios-sdk) explicitly disables this due to SwiftLint conflicts.

---

## 2. Overlapping Rules (Both Tools Handle)

These rules exist in both tools and need coordination:

| Area | SwiftFormat | SwiftLint | Recommendation |
|------|-------------|-----------|----------------|
| Line length | `--maxwidth 120` | `line_length: 120` | Aligned |
| Unused code | N/A | `unused_declaration` | SwiftLint only |
| Empty collections | `isEmpty` | `empty_collection_literal` | Both (complementary) |
| Operator spacing | `--operatorfunc spaced` | `operator_usage_whitespace` | Both (complementary) |
| Vertical whitespace | Various | `vertical_whitespace_*` | Both (complementary) |

---

## 3. SwiftLint-Only Rules (No SwiftFormat Equivalent)

These rules are unique to SwiftLint and should be kept:

- `force_unwrapping` - Critical for safety
- `implicitly_unwrapped_optional` - Critical for safety
- `cyclomatic_complexity` - Code quality metric
- `function_body_length` - Code quality metric
- `file_length` - Code quality metric
- `unused_import` - Dead code detection
- `unused_declaration` - Dead code detection
- `discouraged_optional_boolean` - Swift best practice

---

## 4. SwiftFormat-Only Rules (No SwiftLint Equivalent)

These rules are unique to SwiftFormat:

- `organizeDeclarations` - Organizes type members by category
- `markTypes` - Adds MARK comments
- `wrapEnumCases` - Wraps enum cases
- `wrapSwitchCases` - Wraps switch cases
- `blankLineAfterImports` - Adds blank line after imports

---

## 5. Rules Currently Disabled (Review Needed)

### In SwiftLint (disabled_rules):
| Rule | Reason | Recommendation |
|------|--------|----------------|
| `trailing_comma` | Conflicts with SwiftFormat | Keep disabled |
| `identifier_name` | Too restrictive | Consider enabling with config |
| `type_name` | Too restrictive | Consider enabling with config |
| `nesting` | Limiting for complex types | Keep disabled |

### In SwiftFormat (--disable):
| Rule | Reason | Recommendation |
|------|--------|----------------|
| `acronyms` | May conflict with existing code | Keep disabled |
| `redundantOptionalBinding` | Swift 5.7+ feature, may be too aggressive | Review |
| `wrapMultilineStatementBraces` | SwiftLint conflict | Keep disabled |

---

## 6. Industry Best Practices Summary

### From Airbnb Swift Style Guide:
1. **Formatting should be automated** - Never debate style in PRs
2. **Format rules must be non-destructive** - No semantic changes
3. **Lint rules should have autocorrect** - When possible
4. **Version lock tools** - Use Mint/SPM for consistency

### From Google Swift Style Guide:
1. **4-space indentation** (matches current config)
2. **120 character line limit** (matches current config)
3. **Trailing commas encouraged** for multiline collections

### From Community Research:
1. **Run SwiftFormat first, then SwiftLint** - Format then validate
2. **Disable conflicting SwiftLint rules** - Let SwiftFormat handle formatting
3. **Use SwiftLint for semantic rules** - Things format can't detect

---

## 7. Sources

- [SwiftFormat GitHub](https://github.com/nicklockwood/SwiftFormat)
- [SwiftLint GitHub](https://github.com/realm/SwiftLint)
- [Airbnb Swift Style Guide](https://github.com/airbnb/swift)
- [SwiftLint trailing_comma Reference](https://realm.github.io/SwiftLint/trailing_comma.html)
- [SwiftLint modifier_order Reference](https://realm.github.io/SwiftLint/modifier_order.html)
- [Facebook iOS SDK SwiftFormat Config](https://github.com/facebook/facebook-ios-sdk/blob/main/.swiftformat)
- [Hacking with Swift - SwiftLint Guide](https://www.hackingwithswift.com/articles/97/how-to-clean-up-your-code-formatting-with-swiftlint)

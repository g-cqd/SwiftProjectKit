# SwiftProjectKit

Centralized, opinionated Swift project tooling for g-cqd's projects. Includes swift-format integration, git hooks, static analysis, and CI/CD generation.

## Features

- **Git Hooks System** - Pre-commit and pre-push hooks with auto-fix capabilities
- **swift-format Integration** - Build and command plugins using Xcode's built-in swift-format
- **Static Analysis** - Unused code and duplication detection via SwiftStaticAnalysis
- **CLI Tool (`spk`)** - Project scaffolding, hooks management, and code analysis
- **GitHub Workflow Templates** - Platform-aware CI/CD generation with release support
- **Version Sync** - Keep version numbers consistent across files

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/SwiftProjectKit.git", from: "0.0.21"),
]
```

### Using Build Plugins

Add plugins to your targets:

```swift
.target(
    name: "MyTarget",
    plugins: [
        .plugin(name: "SwiftFormatBuildPlugin", package: "SwiftProjectKit"),
    ]
)
```

### Using Command Plugins

Run on-demand:

```bash
# Format code
swift package format-source-code

# Check formatting (lint mode)
swift package format-source-code --lint
```

## CLI Tool (`spk`)

### Installation

```bash
swift build -c release
cp .build/release/spk /usr/local/bin/
```

### Commands Overview

| Command | Description |
|---------|-------------|
| `spk hooks` | Manage git hooks (setup, run, fix, list) |
| `spk analyze` | Run static analysis (unused, duplicates) |
| `spk init` | Initialize a new project |
| `spk sync` | Sync project to standards |
| `spk format` | Run swift-format |
| `spk workflow` | Generate GitHub workflows |
| `spk update` | Update configuration files |

---

## Git Hooks

The hooks system runs automated checks on commit and push, with auto-fix capabilities.

### Quick Start

```bash
# Set up git hooks for your project
spk hooks setup

# Run hooks manually
spk hooks run pre-commit

# Apply all available fixes
spk hooks fix
```

### `spk hooks setup`

Install git hooks in your repository.

```bash
spk hooks setup [--hooks-path <path>]
```

Creates `.githooks/` directory with `pre-commit` and `pre-push` hooks, and configures git to use them.

### `spk hooks run`

Run hook tasks manually.

```bash
spk hooks run <hook-type> [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `<hook-type>` | Hook to run: `pre-commit`, `pre-push`, `ci` | `pre-commit` |
| `--fix` | Fix mode: `safe`, `cautious`, `all`, `none` | `safe` |
| `--only` | Only run specific tasks (comma-separated) | All tasks |
| `--verbose` | Show detailed output | `false` |

**Examples:**

```bash
# Run pre-commit hooks
spk hooks run pre-commit

# Run without auto-fixing
spk hooks run pre-commit --fix none

# Run only format and build tasks
spk hooks run pre-commit --only format,build

# Run CI tasks
spk hooks run ci
```

### `spk hooks fix`

Apply all available fixes.

```bash
spk hooks fix [--mode <mode>] [--only <tasks>]
```

### `spk hooks list`

List all available hook tasks.

```bash
spk hooks list
```

### Built-in Tasks

| Task | Hooks | Description | Auto-fix |
|------|-------|-------------|----------|
| `format` | pre-commit | Run swift-format | Yes (safe) |
| `build` | pre-commit | Build the project | No |
| `test` | pre-commit, pre-push | Run tests | No |
| `versionSync` | pre-commit, ci | Check version consistency | Yes (safe) |
| `unused` | pre-push, ci | Detect unused code | No |
| `duplicates` | pre-push, ci | Detect code duplication | No |

---

## Static Analysis

### `spk analyze unused`

Find unused code in your project.

```bash
spk analyze unused [paths...] [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--mode` | Analysis mode: `reachability`, `reference` | `reachability` |
| `--exclude-paths` | Paths to exclude | `.build`, `DerivedData` |
| `--sensible-defaults` | Apply sensible filtering | `true` |
| `--strict` | Exit with error if issues found | `false` |

**Examples:**

```bash
# Analyze Sources directory
spk analyze unused Sources/

# Strict mode for CI
spk analyze unused --strict

# Reference mode (less aggressive)
spk analyze unused --mode reference
```

### `spk analyze duplicates`

Find duplicated code blocks.

```bash
spk analyze duplicates [paths...] [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--min-tokens` | Minimum tokens for a clone | `100` |
| `--exclude-paths` | Paths to exclude | `.build`, `DerivedData` |
| `--strict` | Exit with error if issues found | `false` |

**Examples:**

```bash
# Find duplicates in Sources
spk analyze duplicates Sources/

# Lower threshold for more matches
spk analyze duplicates --min-tokens 50
```

---

## Project Commands

### `spk init`

Create a new Swift project with standard configuration files.

```bash
spk init --name <name> [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--name`, `-n` | Project name (required) | - |
| `--type`, `-t` | Project type: `package` or `app` | `package` |
| `--output` | Output directory | Current directory |
| `--no-format` | Skip swift-format configuration | `false` |
| `--no-workflows` | Skip GitHub workflows | `false` |
| `--no-claude` | Skip CLAUDE.md | `false` |

### `spk sync`

Sync project to standards - fills gaps, updates configs, and fixes code.

```bash
spk sync [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--path`, `-p` | Path to project | Current directory |
| `--dry-run` | Preview changes without applying | `false` |
| `--skip-deps` | Skip dependency updates | `false` |
| `--skip-format` | Skip code formatting | `false` |

### `spk format`

Run swift-format on the project.

```bash
spk format [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--path`, `-p` | Path to format | Current directory |
| `--lint` | Check only, don't modify files | `false` |

### `spk workflow generate`

Generate GitHub Actions workflow files.

```bash
spk workflow generate [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--type`, `-t` | Workflow type: `ci` or `all` | `ci` |
| `--macos-only` | Generate macOS-only workflow | `false` |
| `--no-release` | Exclude release jobs | `false` |
| `--force` | Overwrite existing workflows | `false` |

---

## Configuration

### Project Configuration (`.spk.json`)

Central configuration file for SwiftProjectKit:

```json
{
  "version": "1.0",
  "swiftVersion": "6.2",
  "project": {
    "version": "1.0.0"
  },
  "platforms": {
    "macOS": "15.0",
    "iOS": "18.0"
  },
  "hooks": {
    "fixMode": "safe",
    "restageFixed": true,
    "preCommit": {
      "enabled": true,
      "tasks": ["format", "versionSync", "build", "test"]
    },
    "prePush": {
      "enabled": true,
      "tasks": ["test", "unused", "duplicates"]
    },
    "tasks": {
      "format": {
        "enabled": true,
        "paths": ["Sources/", "Tests/"]
      },
      "versionSync": {
        "options": {
          "syncTargets": [
            {
              "file": "Sources/MyLib/Version.swift",
              "pattern": "version = \"(\\d+\\.\\d+\\.\\d+)\""
            }
          ]
        }
      },
      "unused": {
        "blocking": false,
        "paths": ["Sources/"]
      }
    }
  },
  "swiftformat": {
    "enabled": true,
    "configPath": ".swift-format"
  },
  "workflows": {
    "ci": true,
    "release": true
  }
}
```

### Version Sync Configuration

The `versionSync` task ensures version numbers stay consistent. It reads the version from `.spk.json`'s `project.version` field and propagates it to configured files.

```json
{
  "hooks": {
    "tasks": {
      "versionSync": {
        "options": {
          "syncTargets": [
            {
              "file": "Sources/MyLib/MyLib.swift",
              "pattern": "let version = \"(\\d+\\.\\d+\\.\\d+)\""
            },
            {
              "file": "README.md",
              "pattern": "from: \"(\\d+\\.\\d+\\.\\d+)\""
            }
          ]
        }
      }
    }
  }
}
```

To use a file as the version source instead:

```json
{
  "options": {
    "sourceType": "file",
    "sourceFile": "VERSION",
    "syncTargets": [...]
  }
}
```

### Custom Shell Tasks

Add custom tasks that run shell commands:

```json
{
  "hooks": {
    "tasks": {
      "myLinter": {
        "name": "My Custom Linter",
        "command": "my-linter check Sources/",
        "fixCommand": "my-linter fix Sources/",
        "blocking": true,
        "hooks": ["pre-commit"]
      }
    }
  }
}
```

### swift-format (`.swift-format`)

JSON configuration for apple/swift-format:

```json
{
  "version": 1,
  "lineLength": 120,
  "indentation": { "spaces": 4 },
  "tabWidth": 4,
  "maximumBlankLines": 1,
  "rules": {
    "NeverForceUnwrap": true,
    "NeverUseForceTry": true,
    "OrderedImports": true,
    "UseEarlyExits": true
  }
}
```

---

## Architecture

```
SwiftProjectKit/
├── Sources/
│   ├── SwiftProjectKitCore/
│   │   ├── BinaryManagement/    # SWA tool download & caching
│   │   ├── Configuration/       # Project config models
│   │   ├── Hooks/               # Git hooks system
│   │   │   ├── Git/             # Git index operations
│   │   │   └── Tasks/           # Built-in hook tasks
│   │   └── Templates/           # Default configs & workflows
│   └── SwiftProjectKitCLI/
│       └── Commands/            # CLI commands
│           └── Hooks/           # Hooks subcommands
└── Plugins/
    ├── SwiftFormatBuildPlugin/
    ├── SwiftFormatCommandPlugin/
    ├── SWABuildPlugin/
    ├── SWACommandPlugin/
    ├── UnusedCodeBuildPlugin/
    ├── UnusedCodeCommandPlugin/
    ├── DuplicationBuildPlugin/
    └── DuplicationCommandPlugin/
```

## Products

| Product | Type | Description |
|---------|------|-------------|
| `SwiftProjectKitCore` | Library | Configuration, hooks, templates, binary management |
| `spk` | Executable | CLI tool for project management |
| `SwiftFormatBuildPlugin` | Build Plugin | Auto-format on builds |
| `SwiftFormatCommandPlugin` | Command Plugin | On-demand formatting |
| `SWABuildPlugin` | Build Plugin | Static analysis on builds |
| `SWACommandPlugin` | Command Plugin | On-demand static analysis |

## Contributing

After cloning, set up git hooks:

```bash
swift build
.build/debug/spk hooks setup
```

This enables pre-commit and pre-push hooks that run automatically:
- **Pre-commit**: Format, version sync, build, test
- **Pre-push**: Test, unused code detection, duplication detection

To skip hooks temporarily: `git commit --no-verify`

## Requirements

- Swift 6.2+
- macOS 15+
- Xcode 26+

## License

MIT

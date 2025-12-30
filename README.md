# SwiftProjectKit

Centralized, opinionated Swift project tooling for g-cqd's projects. Uses apple/swift-format for code formatting.

## Features

- **swift-format Integration** - Build and command plugins using Xcode's built-in swift-format
- **CLI Tool (`spk`)** - Project scaffolding, sync, and management
- **GitHub Workflow Templates** - Platform-aware CI/CD generation with release support
- **Static Analysis (SWA)** - Unused code and duplication detection plugins
- **Xcode Support** - All plugins work with both SPM and Xcode projects

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/g-cqd/SwiftProjectKit.git", from: "1.0.0"),
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

### Quick Start

```bash
# Create a new project with all configurations
spk init --name MyPackage --type package

# Sync an existing project to standards (recommended)
spk sync

# Preview what sync would do
spk sync --dry-run
```

### Commands Reference

#### `spk init` - Initialize New Project

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

**Examples:**

```bash
# Create a library package
spk init --name MyLibrary --type package

# Create an app without Claude configuration
spk init --name MyApp --type app --no-claude

# Create in specific directory
spk init --name MyPackage --output ~/Projects
```

#### `spk sync` - Sync Project to Standards

The most powerful command - fills gaps, updates configs, and fixes code. This is the recommended way to bring any project up to standards.

```bash
spk sync [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--path`, `-p` | Path to project | Current directory |
| `--dry-run` | Preview changes without applying | `false` |
| `--skip-deps` | Skip dependency updates | `false` |
| `--skip-format` | Skip code formatting | `false` |
| `--verbose` | Show detailed output | `false` |

**What `sync` does:**
1. Detects project type (Swift Package or Xcode)
2. Creates missing config files (`.swift-format`, `.gitignore`, `CLAUDE.md`, CI workflow)
3. Updates package dependencies
4. Runs swift-format to fix formatting

**Examples:**

```bash
# Sync current project
spk sync

# Preview what would change
spk sync --dry-run

# Sync without touching dependencies
spk sync --skip-deps

# Sync with verbose output
spk sync --verbose
```

#### `spk update` - Update Configuration Files

Update specific configuration files to latest standards.

```bash
spk update [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--path`, `-p` | Path to project | Current directory |
| `--all` | Update all configurations | `false` |
| `--format` | Update swift-format rules | `false` |
| `--workflows` | Update GitHub workflows | `false` |
| `--claude` | Update CLAUDE.md | `false` |
| `--dry-run` | Preview changes without applying | `false` |

**Examples:**

```bash
# Update everything
spk update --all

# Update only format config
spk update --format

# Preview workflow updates
spk update --workflows --dry-run
```

#### `spk format` - Run swift-format

Run swift-format on the project using Xcode's built-in toolchain.

```bash
spk format [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--path`, `-p` | Path to format | Current directory |
| `--lint` | Check only, don't modify files | `false` |
| `--verbose` | Show detailed output | `false` |

**Examples:**

```bash
# Format current project
spk format

# Check formatting without changes (for CI)
spk format --lint

# Format with verbose output
spk format --verbose
```

#### `spk workflow` - Manage GitHub Workflows

Generate GitHub Actions workflow files.

```bash
spk workflow generate [options]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--type`, `-t` | Workflow type: `ci` or `all` | `ci` |
| `--name`, `-n` | Project name (auto-detected) | From Package.swift |
| `--path`, `-p` | Project path | Current directory |
| `--macos-only` | Generate macOS-only workflow | `false` |
| `--no-release` | Exclude release jobs from CI | `false` |
| `--force` | Overwrite existing workflows | `false` |

**Examples:**

```bash
# Generate CI workflow (includes release support)
spk workflow generate

# Generate without release jobs
spk workflow generate --no-release

# macOS-only project
spk workflow generate --macos-only

# Force overwrite existing
spk workflow generate --force
```

## Products

| Product | Type | Description |
|---------|------|-------------|
| `SwiftProjectKitCore` | Library | Configuration models, templates, and binary management |
| `spk` | Executable | CLI tool for project management |
| `SwiftFormatBuildPlugin` | Build Plugin | Run swift-format automatically on builds |
| `SwiftFormatCommandPlugin` | Command Plugin | On-demand formatting via `swift package` |
| `SWABuildPlugin` | Build Plugin | Run static analysis on builds |
| `SWACommandPlugin` | Command Plugin | On-demand static analysis |

## Configuration

### Project Configuration (`.swiftprojectkit.json`)

Optional configuration file for customizing SwiftProjectKit behavior:

```json
{
  "version": "1.0",
  "swiftVersion": "6.2",
  "platforms": {
    "iOS": "18.0",
    "macOS": "15.0",
    "watchOS": null,
    "tvOS": null,
    "visionOS": null
  },
  "swiftformat": {
    "enabled": true,
    "configPath": null
  },
  "workflows": {
    "ci": true,
    "release": true,
    "docs": true
  }
}
```

### swift-format (`.swift-format`)

Place in project root. This is a JSON configuration file for apple/swift-format. If not present, `spk` uses built-in defaults optimized for modern Swift:

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

## Architecture

```
SwiftProjectKit/
├── Sources/
│   ├── SwiftProjectKitCore/     # Shared library
│   │   ├── BinaryManagement/    # SWA tool download & caching
│   │   ├── Configuration/       # Project config models
│   │   └── Templates/           # Default configs & workflows
│   └── SwiftProjectKitCLI/      # CLI executable
│       └── Commands/            # CLI commands
└── Plugins/                     # SPM plugins
    ├── SwiftFormatBuildPlugin/
    ├── SwiftFormatCommandPlugin/
    ├── SWABuildPlugin/
    ├── SWACommandPlugin/
    ├── UnusedCodeBuildPlugin/
    ├── UnusedCodeCommandPlugin/
    ├── DuplicationBuildPlugin/
    └── DuplicationCommandPlugin/
```

## Contributing

After cloning, install git hooks to ensure code quality:

```bash
./scripts/install-hooks.sh
```

This enables pre-commit checks that run automatically before each commit:
- Code formatting (swift-format)
- Version consistency
- Build verification
- Test suite

To skip hooks for a specific commit: `git commit --no-verify`

## Requirements

- Swift 6.2+
- macOS 15+ / iOS 18+
- Xcode 26+

## License

MIT

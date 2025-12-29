# SwiftProjectKit

Centralized, opinionated Swift project tooling for g-cqd's projects.

## Features

- **SwiftLint Integration** - Build and command plugins with automatic binary download
- **SwiftFormat Integration** - Build and command plugins with automatic binary download
- **CLI Tool (`spk`)** - Project scaffolding and management
- **GitHub Workflow Templates** - Platform-aware CI/CD generation
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
        .plugin(name: "SwiftLintBuildPlugin", package: "SwiftProjectKit"),
        .plugin(name: "SwiftFormatBuildPlugin", package: "SwiftProjectKit"),
    ]
)
```

### Using Command Plugins

Run on-demand:

```bash
# Lint code
swift package --allow-network-connections all lint

# Format code
swift package --allow-writing-to-package-directory format-source-code
```

## CLI Tool

### Install

```bash
swift build -c release
cp .build/release/spk /usr/local/bin/
```

### Commands

```bash
# Create new project
spk init --name MyPackage --type package

# Update configurations
spk update --all

# Lint code
spk lint --fix

# Format code
spk format

# Generate workflows
spk workflow generate --type ci
```

## Products

| Product | Type | Description |
|---------|------|-------------|
| `SwiftProjectKitCore` | Library | Configuration models and templates |
| `spk` | Executable | CLI tool |
| `SwiftLintBuildPlugin` | Build Plugin | Run SwiftLint on builds |
| `SwiftFormatBuildPlugin` | Build Plugin | Run SwiftFormat on builds |
| `SwiftLintCommandPlugin` | Command Plugin | On-demand linting |
| `SwiftFormatCommandPlugin` | Command Plugin | On-demand formatting |

## Configuration

### SwiftLint

Place `.swiftlint.yml` in your project root. If not present, the plugin uses built-in defaults.

### SwiftFormat

Place `.swiftformat` in your project root. If not present, the plugin uses built-in defaults.

## Requirements

- Swift 6.2+
- macOS 15+ / iOS 18+
- Xcode 26+

## License

MIT

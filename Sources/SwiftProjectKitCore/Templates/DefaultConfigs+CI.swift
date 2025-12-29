import Foundation

// MARK: - CI Workflow

public extension DefaultConfigs {
    static func ciWorkflow(name: String, platforms: PlatformConfiguration) -> String {
        var workflow = ciWorkflowHeader()
        workflow += ciLintJob()
        workflow += ciBuildAndTestJob()
        workflow += ciCodeQLJob()

        if platforms.enabledPlatforms.count > 1 {
            workflow += ciPlatformMatrixJob(name: name, platforms: platforms)
        }

        return workflow
    }
}

// MARK: - CI Workflow Components

extension DefaultConfigs {
    static func ciWorkflowHeader() -> String {
        """
        name: CI

        on:
          push:
            branches: [main]
          pull_request:
            branches: [main]

        permissions:
          contents: read

        concurrency:
          group: ${{ github.workflow }}-${{ github.ref }}
          cancel-in-progress: true

        jobs:
        """
    }

    static func ciLintJob() -> String {
        """

          lint:
            name: Lint
            runs-on: macos-15
            steps:
              - uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_26.1.1.app

              - name: Install Linting Tools
                run: brew install swiftlint swiftformat || true

              - name: SwiftLint
                run: swiftlint lint --strict --reporter github-actions-logging

              - name: SwiftFormat
                run: swiftformat --lint .

        """
    }

    static func ciBuildAndTestJob() -> String {
        """
          build-and-test:
            name: Build & Test
            runs-on: macos-15
            needs: lint
            steps:
              - uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_26.1.1.app

              - name: Install Linting Tools
                run: brew install swiftlint swiftformat || true

              - name: Build
                run: swift build -c release

              - name: Run Tests
                run: swift test --parallel

        """
    }

    static func ciCodeQLJob() -> String {
        """
          codeql:
            name: CodeQL Analysis
            runs-on: macos-15
            needs: lint
            permissions:
              security-events: write
              actions: read
              contents: read
            steps:
              - uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_26.1.1.app

              - name: Install Linting Tools
                run: brew install swiftlint swiftformat || true

              - name: Initialize CodeQL
                uses: github/codeql-action/init@v3
                with:
                  languages: swift
                  build-mode: manual

              - name: Build for CodeQL
                run: swift build -c release --arch arm64

              - name: Perform CodeQL Analysis
                uses: github/codeql-action/analyze@v3
                with:
                  category: "/language:swift"
        """
    }

    static func ciPlatformMatrixJob(
        name: String,
        platforms: PlatformConfiguration,
    ) -> String {
        let platformEntries = buildPlatformEntries(platforms: platforms)

        return """

          build-platforms:
            name: Build (${{ matrix.platform }})
            runs-on: macos-15
            needs: lint
            strategy:
              matrix:
                include:
        \(platformEntries.joined(separator: "\n"))
            steps:
              - uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_26.1.1.app

              - name: Install Linting Tools
                run: brew install swiftlint swiftformat || true

              - name: Build for ${{ matrix.platform }}
                run: |
                  xcodebuild build \\
                    -scheme \(name) \\
                    -destination '${{ matrix.destination }}' \\
                    -skipPackagePluginValidation \\
                    CODE_SIGNING_ALLOWED=NO
        """
    }

    static func buildPlatformEntries(platforms: PlatformConfiguration) -> [String] {
        var entries: [String] = []

        if platforms.iOS != nil {
            entries.append("""
                      - platform: iOS
                        destination: 'generic/platform=iOS Simulator'
            """)
        }
        if platforms.macOS != nil {
            entries.append("""
                      - platform: macOS
                        destination: 'platform=macOS'
            """)
        }
        if platforms.tvOS != nil {
            entries.append("""
                      - platform: tvOS
                        destination: 'generic/platform=tvOS Simulator'
            """)
        }
        if platforms.watchOS != nil {
            entries.append("""
                      - platform: watchOS
                        destination: 'generic/platform=watchOS Simulator'
            """)
        }
        if platforms.visionOS != nil {
            entries.append("""
                      - platform: visionOS
                        destination: 'generic/platform=visionOS Simulator'
            """)
        }

        return entries
    }
}

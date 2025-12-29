import Foundation

// MARK: - Unified CI/CD Workflow

public extension DefaultConfigs {
    /// Generates a unified CI/CD workflow with conditional release jobs.
    /// - Parameters:
    ///   - name: The project name (used in release notes)
    ///   - platforms: Platform configuration for matrix builds
    ///   - includeRelease: Whether to include release jobs (default: true)
    /// - Returns: The complete workflow YAML string
    static func ciWorkflow(
        name: String,
        platforms: PlatformConfiguration,
        includeRelease: Bool = true,
    ) -> String {
        var workflow = ciWorkflowHeader(includeRelease: includeRelease)
        workflow += ciLintJob()
        workflow += ciBuildAndTestJob()
        workflow += ciCodeQLJob()

        if platforms.enabledPlatforms.count > 1 {
            workflow += ciPlatformMatrixJob(name: name, platforms: platforms)
        }

        if includeRelease {
            workflow += ciValidateReleaseJob()
            workflow += ciChangelogJob()
            workflow += ciCreateReleaseJob(name: name)
        }

        return workflow
    }
}

// MARK: - Workflow Header

extension DefaultConfigs {
    // swiftlint:disable:next function_body_length
    static func ciWorkflowHeader(includeRelease: Bool) -> String {
        let triggers = includeRelease ? """
        on:
          push:
            branches: [main]
            tags: ['v*']
          pull_request:
            branches: [main]
          workflow_dispatch:
            inputs:
              version:
                description: 'Version to release (e.g., 1.2.0)'
                required: true
                type: string
              create_tag:
                description: 'Create git tag'
                required: true
                type: boolean
                default: true
        """ : """
        on:
          push:
            branches: [main]
          pull_request:
            branches: [main]
        """

        let permissions = includeRelease ? """
        permissions:
          contents: write
          security-events: write
        """ : """
        permissions:
          contents: read
          security-events: write
        """

        return """
        name: CI/CD

        \(triggers)

        \(permissions)

        concurrency:
          group: ${{ github.workflow }}-${{ github.ref }}
          cancel-in-progress: ${{ github.event_name == 'pull_request' }}

        env:
          XCODE_VERSION: '\(defaultXcodeVersion)'

        jobs:
        """
    }
}

// MARK: - CI Jobs

extension DefaultConfigs {
    static func ciLintJob() -> String {
        """

          # ==========================================================================
          # Stage 1: Code Quality (Always runs)
          # ==========================================================================
          lint:
            name: Lint
            runs-on: macos-15
            steps:
              - uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

              - name: Ensure Linting Tools
                run: |
                  command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
                  command -v swiftformat >/dev/null 2>&1 || brew install swiftformat

              - name: SwiftLint
                run: swiftlint lint --strict --reporter github-actions-logging

              - name: SwiftFormat
                run: swiftformat --lint .

        """
    }

    static func ciBuildAndTestJob() -> String {
        """
          # ==========================================================================
          # Stage 2: Build & Test (Always runs, depends on lint)
          # ==========================================================================
          build-and-test:
            name: Build & Test
            runs-on: macos-15
            needs: lint
            steps:
              - uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

              - name: Cache SPM Dependencies
                uses: actions/cache@v4
                with:
                  path: |
                    .build
                    ~/Library/Developer/Xcode/DerivedData
                  key: spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
                  restore-keys: spm-${{ runner.os }}-

              - name: Ensure Linting Tools
                run: |
                  command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
                  command -v swiftformat >/dev/null 2>&1 || brew install swiftformat

              - name: Build
                run: swift build -c release

              - name: Run Tests
                run: swift test --parallel

        """
    }

    // swiftlint:disable:next function_body_length
    static func ciCodeQLJob() -> String {
        """
          # ==========================================================================
          # Stage 3: Security Analysis (Always runs, depends on lint)
          # ==========================================================================
          codeql:
            name: CodeQL Analysis
            runs-on: macos-15
            needs: lint
            steps:
              - uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

              - name: Cache SPM Dependencies
                uses: actions/cache@v4
                with:
                  path: |
                    .build
                    ~/Library/Developer/Xcode/DerivedData
                  key: spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
                  restore-keys: spm-${{ runner.os }}-

              - name: Ensure Linting Tools
                run: |
                  command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
                  command -v swiftformat >/dev/null 2>&1 || brew install swiftformat

              - name: Initialize CodeQL
                uses: github/codeql-action/init@v4
                with:
                  languages: swift
                  build-mode: manual

              - name: Build for CodeQL
                run: swift build -c release --arch arm64

              - name: Perform CodeQL Analysis
                uses: github/codeql-action/analyze@v4
                with:
                  category: "/language:swift"

        """
    }

    // swiftlint:disable:next function_body_length
    static func ciPlatformMatrixJob(
        name: String,
        platforms: PlatformConfiguration,
    ) -> String {
        let platformEntries = buildPlatformEntries(platforms: platforms)

        return """
          # ==========================================================================
          # Stage 4: Platform Matrix Build (PRs and main branch)
          # ==========================================================================
          build-platforms:
            name: Build (${{ matrix.platform }})
            runs-on: macos-15
            needs: lint
            if: >-
              github.event_name == 'pull_request' ||
              (github.event_name == 'push' && github.ref == 'refs/heads/main')
            strategy:
              matrix:
                include:
        \(platformEntries.joined(separator: "\n"))
            steps:
              - uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

              - name: Cache SPM Dependencies
                uses: actions/cache@v4
                with:
                  path: |
                    .build
                    ~/Library/Developer/Xcode/DerivedData
                  key: spm-${{ runner.os }}-xcode-${{ hashFiles('Package.resolved') }}
                  restore-keys: spm-${{ runner.os }}-xcode-

              - name: Ensure Linting Tools
                run: |
                  command -v swiftlint >/dev/null 2>&1 || brew install swiftlint
                  command -v swiftformat >/dev/null 2>&1 || brew install swiftformat

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

// MARK: - Release Jobs

extension DefaultConfigs {
    // swiftlint:disable:next function_body_length
    static func ciValidateReleaseJob() -> String {
        """
          # ==========================================================================
          # Stage 5: Release Validation (Tags and workflow_dispatch only)
          # ==========================================================================
          validate-release:
            name: Validate Release
            runs-on: macos-15
            needs: build-and-test
            if: >-
              github.event_name == 'workflow_dispatch' ||
              startsWith(github.ref, 'refs/tags/v')
            outputs:
              version: ${{ steps.version.outputs.version }}
              previous_tag: ${{ steps.previous.outputs.tag }}
            steps:
              - uses: actions/checkout@v4
                with:
                  fetch-depth: 0

              - name: Determine Version
                id: version
                run: |
                  if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
                    VERSION="${{ inputs.version }}"
                  elif [[ "$GITHUB_REF" == refs/tags/v* ]]; then
                    VERSION="${GITHUB_REF#refs/tags/v}"
                  else
                    # Auto-increment: get latest tag and bump patch version
                    LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
                    LATEST_VERSION="${LATEST_TAG#v}"

                    # Parse semver
                    IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST_VERSION"
                    PATCH=$((PATCH + 1))
                    VERSION="${MAJOR}.${MINOR}.${PATCH}"

                    echo "Auto-incrementing from $LATEST_VERSION to $VERSION"
                  fi
                  echo "version=$VERSION" >> $GITHUB_OUTPUT
                  echo "Releasing version: $VERSION"

              - name: Get Previous Tag
                id: previous
                run: |
                  PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
                  echo "tag=$PREV_TAG" >> $GITHUB_OUTPUT

        """
    }

    static func ciChangelogJob() -> String {
        """
          # ==========================================================================
          # Stage 6: Generate Changelog (Tags and workflow_dispatch, runs on Linux)
          # ==========================================================================
          changelog:
            name: Generate Changelog
            runs-on: ubuntu-latest
            needs: validate-release
            outputs:
              changelog: ${{ steps.generate.outputs.changelog }}
            steps:
              - uses: actions/checkout@v4
                with:
                  fetch-depth: 0

              - name: Generate Changelog
                id: generate
                run: |
                  PREV_TAG="${{ needs.validate-release.outputs.previous_tag }}"
                  VERSION="${{ needs.validate-release.outputs.version }}"

                  {
                    echo 'changelog<<EOF'
                    echo "## What's Changed in v$VERSION"
                    echo ""

                    if [[ -n "$PREV_TAG" ]]; then
                      echo "### Commits"
                      git log $PREV_TAG..HEAD --pretty=format:"- %h %s (%an)" | head -50
                    else
                      echo "Initial release"
                      git log --pretty=format:"- %h %s (%an)" | head -50
                    fi

                    echo ""
                    echo 'EOF'
                  } >> $GITHUB_OUTPUT

        """
    }

    // swiftlint:disable function_body_length
    static func ciCreateReleaseJob(name: String) -> String {
        """
          # ==========================================================================
          # Stage 7: Create GitHub Release (Tags and workflow_dispatch)
          # ==========================================================================
          release:
            name: Create Release
            runs-on: macos-15
            needs: [validate-release, changelog]
            steps:
              - uses: actions/checkout@v4

              - name: Create Tag
                if: github.event_name == 'workflow_dispatch' && inputs.create_tag
                run: |
                  git config user.name "github-actions[bot]"
                  git config user.email "github-actions[bot]@users.noreply.github.com"
                  git tag -a "v${{ needs.validate-release.outputs.version }}" \\
                    -m "Release v${{ needs.validate-release.outputs.version }}"
                  git push origin "v${{ needs.validate-release.outputs.version }}"

              - name: Prepare Release Notes
                run: |
                  cat > release_notes.md << 'RELEASE_EOF'
                  # \(name) v${{ needs.validate-release.outputs.version }}

                  ${{ needs.changelog.outputs.changelog }}

                  ---

                  ## Installation

                  ### Swift Package Manager

                  ```swift
                  dependencies: [
                      .package(
                          url: "https://github.com/g-cqd/\(name).git",
                          from: "${{ needs.validate-release.outputs.version }}"
                      )
                  ]
                  ```

                  RELEASE_EOF

              - name: Create GitHub Release
                uses: softprops/action-gh-release@v2
                with:
                  tag_name: v${{ needs.validate-release.outputs.version }}
                  name: \(name) v${{ needs.validate-release.outputs.version }}
                  body_path: release_notes.md
                  draft: false
                  prerelease: ${{ \
        contains(needs.validate-release.outputs.version, 'alpha') || \
        contains(needs.validate-release.outputs.version, 'beta') || \
        contains(needs.validate-release.outputs.version, 'rc') \
        }}
                env:
                  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        """
    }
    // swiftlint:enable function_body_length
}

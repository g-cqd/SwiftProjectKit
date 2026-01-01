// swa:ignore-file-length
// Template files benefit from keeping related templates together
import Foundation

// MARK: - Unified CI/CD Workflow

extension DefaultConfigs {
    /// Default SWA version for CI workflows
    public static let defaultSWAVersion = "0.0.23"

    /// Default Xcode version for CI workflows
    public static let defaultXcodeVersion = "26.1.1"

    /// Generates a unified CI/CD workflow with conditional release jobs.
    /// - Parameters:
    ///   - name: The project name (used in release notes)
    ///   - platforms: Platform configuration for matrix builds
    ///   - includeRelease: Whether to include release jobs (default: true)
    ///   - includePlatformMatrix: Whether to include platform matrix builds (default: false for CLI/tooling)
    ///   - includeBinaryRelease: Whether to build and package universal binaries for CLI tools (default: false)
    ///   - binaryName: The executable name to package (defaults to lowercased project name)
    ///   - includeHomebrew: Whether to generate Homebrew formula (default: false, requires includeBinaryRelease)
    ///   - homebrewTap: The Homebrew tap name (e.g., "g-cqd/tap")
    ///   - useSpk: Whether to use spk for CI tasks (format, build, test via hooks)
    ///   - includeStaticAnalysis: Whether to include unused/duplicates checks (default: false)
    ///   - swaVersion: SwiftStaticAnalysis version for static analysis (default: 1.0.6)
    ///   - includeDocs: Whether to include documentation generation and deployment (default: false)
    ///   - docsTarget: The target to generate documentation for (required if includeDocs is true)
    ///   - hostingBasePath: The base path for static hosting, usually the repo name (defaults to project name)
    /// - Returns: The complete workflow YAML string
    public static func ciWorkflow(
        name: String,
        platforms: PlatformConfiguration,
        includeRelease: Bool = true,
        includePlatformMatrix: Bool = false,
        includeBinaryRelease: Bool = false,
        binaryName: String? = nil,
        includeHomebrew: Bool = false,
        homebrewTap: String? = nil,
        useSpk: Bool = false,
        includeStaticAnalysis: Bool = false,
        swaVersion: String = defaultSWAVersion,
        includeDocs: Bool = false,
        docsTarget: String? = nil,
        hostingBasePath: String? = nil
    ) -> String {
        let resolvedBinaryName = binaryName ?? name.lowercased()

        var workflow = ciWorkflowHeader(
            includeRelease: includeRelease,
            includeDocs: includeDocs,
            includeStaticAnalysis: includeStaticAnalysis,
            swaVersion: swaVersion
        )

        // Stage 1: Setup (if static analysis is enabled)
        if includeStaticAnalysis {
            workflow += ciSetupSWAJob(swaVersion: swaVersion)
        }

        // Stage 2: Quality checks (parallel)
        if useSpk {
            workflow += ciSpkLintJob(needsSetup: includeStaticAnalysis)
        } else {
            workflow += ciLintJob(needsSetup: includeStaticAnalysis)
        }

        if includeStaticAnalysis {
            workflow += ciUnusedCheckJob()
            workflow += ciDuplicatesCheckJob()
        }

        // Stage 3: Tests (after quality checks)
        if useSpk {
            workflow += ciSpkBuildAndTestJob(
                needsQualityChecks: true,
                includeStaticAnalysis: includeStaticAnalysis
            )
        } else {
            workflow += ciBuildAndTestJob(
                needsQualityChecks: true,
                includeStaticAnalysis: includeStaticAnalysis
            )
        }

        // Stage 4: CodeQL (after tests)
        workflow += ciCodeQLJob(needsTest: true)

        // Only include platform matrix if explicitly requested AND multiple platforms configured
        if includePlatformMatrix, platforms.enabledPlatforms.count > 1 {
            workflow += ciPlatformMatrixJob(name: name, platforms: platforms)
        }

        if includeRelease {
            workflow += ciPrepareReleaseJob()
            if includeBinaryRelease {
                workflow += ciCreateBinaryReleaseJob(
                    name: name,
                    binaryName: resolvedBinaryName,
                    includeHomebrew: includeHomebrew,
                    homebrewTap: homebrewTap,
                )
            } else {
                workflow += ciCreateReleaseJob(name: name)
            }
        }

        // Documentation generation and deployment
        if includeDocs, let target = docsTarget {
            let basePath = hostingBasePath ?? name
            workflow += ciDocsJob(targetName: target, hostingBasePath: basePath)
            workflow += ciDeployDocsJob()
        }

        return workflow
    }
}

// MARK: - Workflow Header

extension DefaultConfigs {
    // swa:ignore-complexity
    static func ciWorkflowHeader(
        includeRelease: Bool,
        includeDocs: Bool = false,
        includeStaticAnalysis: Bool = false,
        swaVersion: String = defaultSWAVersion
    ) -> String {
        let triggers =
            includeRelease
            ? """
            on:
              push:
                branches: [main]
                tags: ['v*']
              pull_request:
                branches: [main]
              workflow_dispatch:
                inputs:
                  release:
                    description: 'Create release'
                    type: boolean
                    default: false
                  version:
                    description: 'Version override (e.g., 1.0.0)'
                    required: false
            """
            : """
            on:
              push:
                branches: [main]
              pull_request:
                branches: [main]
            """

        var permissionLines = ["permissions:"]
        permissionLines.append("  contents: \(includeRelease ? "write" : "read")")
        if includeDocs {
            permissionLines.append("  pages: write")
            permissionLines.append("  id-token: write")
        }
        permissionLines.append("  security-events: write")
        let permissions = permissionLines.joined(separator: "\n")

        let envVars =
            includeStaticAnalysis
            ? """
            env:
              XCODE_VERSION: '\(defaultXcodeVersion)'
              SWA_VERSION: '\(swaVersion)'
            """
            : """
            env:
              XCODE_VERSION: '\(defaultXcodeVersion)'
            """

        return """
            name: CI/CD

            \(triggers)

            \(permissions)

            concurrency:
              group: ${{ github.workflow }}-${{ github.ref }}
              cancel-in-progress: ${{ github.event_name == 'pull_request' }}

            \(envVars)

            jobs:
            """
    }
}

// MARK: - Setup Job

extension DefaultConfigs {
    /// Job that caches SWA binary for static analysis and uploads as artifact
    static func ciSetupSWAJob(swaVersion: String = defaultSWAVersion) -> String {
        """

          # ==========================================================================
          # Stage 1: Setup SWA
          # ==========================================================================
          setup-swa:
            name: Setup SWA
            runs-on: macos-15
            steps:
              - name: Cache SWA Binary
                id: cache-swa
                uses: actions/cache@v4
                with:
                  path: /usr/local/bin/swa
                  key: swa-${{ runner.os }}-${{ env.SWA_VERSION }}

              - name: Download SWA
                if: steps.cache-swa.outputs.cache-hit != 'true'
                run: |
                  DOWNLOAD_URL="https://github.com/g-cqd/SwiftStaticAnalysis/releases/download/v${{ env.SWA_VERSION }}/swa-${{ env.SWA_VERSION }}-macos-universal.tar.gz"
                  echo "Downloading SWA from ${DOWNLOAD_URL}..."
                  curl -fsSL "$DOWNLOAD_URL" -o /tmp/swa.tar.gz
                  tar -xzf /tmp/swa.tar.gz -C /tmp
                  sudo mv /tmp/swa /usr/local/bin/swa
                  sudo chmod +x /usr/local/bin/swa
                  echo "Installed SWA ${{ env.SWA_VERSION }}"

              - name: Upload SWA Binary
                uses: actions/upload-artifact@v4
                with:
                  name: swa-binary
                  path: /usr/local/bin/swa
                  retention-days: 1

        """
    }

    /// Job that checks for unused code
    static func ciUnusedCheckJob() -> String {
        """
          unused-check:
            name: Unused Code Check
            runs-on: macos-15
            needs: setup-swa
            steps:
              - name: Checkout
                uses: actions/checkout@v4

              - name: Download SWA Binary
                uses: actions/download-artifact@v4
                with:
                  name: swa-binary
                  path: /tmp

              - name: Setup SWA
                run: |
                  sudo mv /tmp/swa /usr/local/bin/swa
                  sudo chmod +x /usr/local/bin/swa

              - name: Check Unused Code
                run: |
                  swa unused Sources \\
                    --mode reachability \\
                    --sensible-defaults \\
                    --format text
                continue-on-error: true

        """
    }

    /// Job that checks for code duplication
    static func ciDuplicatesCheckJob() -> String {
        """
          duplicates-check:
            name: Duplicates Check
            runs-on: macos-15
            needs: setup-swa
            steps:
              - name: Checkout
                uses: actions/checkout@v4

              - name: Download SWA Binary
                uses: actions/download-artifact@v4
                with:
                  name: swa-binary
                  path: /tmp

              - name: Setup SWA
                run: |
                  sudo mv /tmp/swa /usr/local/bin/swa
                  sudo chmod +x /usr/local/bin/swa

              - name: Check Duplicates
                run: |
                  swa duplicates Sources \\
                    --min-tokens 100 \\
                    --format text
                continue-on-error: true

        """
    }
}

// MARK: - CI Jobs

extension DefaultConfigs {
    /// Reusable step to setup spk binary (download latest release or build from source)
    static func setupSpkStep(binaryName: String = "spk") -> String {
        """
              - name: Setup SPK
                id: setup-spk
                run: |
                  SPK_BINARY=".build/debug/\(binaryName)"
                  SPK_AVAILABLE=false

                  # Get latest release tag from GitHub
                  echo "Fetching latest spk release..."
                  LATEST_TAG=$(curl -sI "https://github.com/g-cqd/SwiftProjectKit/releases/latest" | grep -i "^location:" | sed 's/.*tag\\///' | tr -d '\\r\\n')

                  if [[ -n "$LATEST_TAG" ]]; then
                    SPK_VERSION="${LATEST_TAG#v}"
                    DOWNLOAD_URL="https://github.com/g-cqd/SwiftProjectKit/releases/download/${LATEST_TAG}/\(
            binaryName
        )-${SPK_VERSION}-macos-universal.tar.gz"
                    echo "Attempting to download spk ${LATEST_TAG}..."
                    if curl -fsSL "$DOWNLOAD_URL" -o /tmp/spk.tar.gz 2>/dev/null; then
                      mkdir -p .build/debug
                      tar -xzf /tmp/spk.tar.gz -C .build/debug
                      chmod +x "$SPK_BINARY"
                      SPK_AVAILABLE=true
                      echo "Downloaded spk ${LATEST_TAG}"
                    fi
                  fi

                  # Fall back to building from source
                  if [[ "$SPK_AVAILABLE" != "true" ]]; then
                    echo "Building spk from source..."
                    swift build --product \(binaryName)
                    echo "Built spk from source"
                  fi

                  echo "spk_path=$SPK_BINARY" >> $GITHUB_OUTPUT
        """
    }

    static func ciLintJob(needsSetup: Bool = false) -> String {
        let needs = needsSetup ? "\n    needs: setup-swa" : ""
        let stageLabel = needsSetup ? "Stage 2" : "Stage 1"

        return """

              # ==========================================================================
              # \(stageLabel): Code Quality (Always runs)
              # ==========================================================================
              format-check:
                name: Format Check
                runs-on: macos-15\(needs)
                steps:
                  - name: Checkout
                    uses: actions/checkout@v4

                  - name: Select Xcode
                    run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

                  - name: Check Formatting
                    run: |
                      # Read paths from .spk.json if available
                      if [[ -f ".spk.json" ]] && command -v jq &> /dev/null; then
                        PATHS=$(jq -r '.hooks.tasks.format.paths // ["Sources/", "Tests/", "Plugins/"] | .[]' .spk.json | tr '\\n' ' ')
                      else
                        PATHS="Sources/ Tests/ Plugins/"
                      fi

                      # Find all Swift files
                      FILES=$(find $PATHS -name '*.swift' 2>/dev/null)

                      # Run swift-format on files
                      if [[ -n "$FILES" ]]; then
                        echo "$FILES" | xargs swift format lint --strict --parallel --ignore-unparsable-files
                      else
                        echo "No Swift files to check"
                      fi

            """
    }

    /// SPK-based lint job using spk format
    static func ciSpkLintJob(needsSetup: Bool = false) -> String {
        let needs = needsSetup ? "\n    needs: setup-swa" : ""
        let stageLabel = needsSetup ? "Stage 2" : "Stage 1"

        return """

              # ==========================================================================
              # \(stageLabel): Code Quality (Always runs)
              # ==========================================================================
              format-check:
                name: Format Check
                runs-on: macos-15\(needs)
                steps:
                  - uses: actions/checkout@v4

                  - name: Select Xcode
                    run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

                  - name: Cache SPM Dependencies
                    uses: actions/cache@v4
                    with:
                      path: .build
                      key: spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
                      restore-keys: spm-${{ runner.os }}-

            \(setupSpkStep())

                  - name: Check Formatting
                    run: ${{ steps.setup-spk.outputs.spk_path }} format --lint

            """
    }

    static func ciBuildAndTestJob(
        needsQualityChecks: Bool = true,
        includeStaticAnalysis: Bool = false
    ) -> String {
        let needs: String
        if includeStaticAnalysis {
            needs = "[format-check, duplicates-check, unused-check]"
        } else {
            needs = needsQualityChecks ? "format-check" : ""
        }

        let needsClause = needs.isEmpty ? "" : "\n    needs: \(needs)"

        let ifClause =
            includeStaticAnalysis
            ? """

                if: |
                  always() &&
                  needs.format-check.result == 'success' &&
                  (needs.duplicates-check.result == 'success' || needs.duplicates-check.result == 'skipped') &&
                  (needs.unused-check.result == 'success' || needs.unused-check.result == 'skipped')
            """ : ""

        let stageLabel = includeStaticAnalysis ? "Stage 3" : "Stage 2"

        return """
              # ==========================================================================
              # \(stageLabel): Test with Coverage
              # ==========================================================================
              test:
                name: Test
                runs-on: macos-15\(needsClause)\(ifClause)
                steps:
                  - name: Checkout
                    uses: actions/checkout@v4

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

                  - name: Run Tests with Coverage
                    run: swift test --parallel --enable-code-coverage

                  - name: Generate Coverage Report
                    run: |
                      BIN_PATH=$(swift build --show-bin-path)
                      XCTEST_PATH=$(find "$BIN_PATH" -name '*.xctest' -type d | head -1)
                      PROFDATA_PATH=$(find .build -name 'default.profdata' -type f | head -1)

                      if [[ -n "$XCTEST_PATH" && -n "$PROFDATA_PATH" ]]; then
                        EXEC_NAME=$(basename "$XCTEST_PATH" .xctest)
                        EXEC_PATH="$XCTEST_PATH/Contents/MacOS/$EXEC_NAME"

                        xcrun llvm-cov export \\
                          "$EXEC_PATH" \\
                          -instr-profile="$PROFDATA_PATH" \\
                          -format=lcov \\
                          -ignore-filename-regex='.build|Tests|Fixtures' \\
                          > coverage.lcov

                        xcrun llvm-cov report \\
                          "$EXEC_PATH" \\
                          -instr-profile="$PROFDATA_PATH" \\
                          -ignore-filename-regex='.build|Tests|Fixtures' \\
                          > coverage.txt

                        echo "Coverage Summary:"
                        cat coverage.txt
                      else
                        echo "Could not find xctest or profdata files"
                      fi
                    continue-on-error: true

                  - name: Upload Coverage Artifact
                    uses: actions/upload-artifact@v4
                    with:
                      name: coverage-report
                      path: |
                        coverage.lcov
                        coverage.txt
                      retention-days: 30
                    continue-on-error: true

            """
    }

    /// SPK-based test job using hooks
    static func ciSpkBuildAndTestJob(
        needsQualityChecks: Bool = true,
        includeStaticAnalysis: Bool = false
    ) -> String {
        let needs: String
        if includeStaticAnalysis {
            needs = "[format-check, duplicates-check, unused-check]"
        } else {
            needs = needsQualityChecks ? "format-check" : ""
        }

        let needsClause = needs.isEmpty ? "" : "\n    needs: \(needs)"

        let ifClause =
            includeStaticAnalysis
            ? """

                if: |
                  always() &&
                  needs.format-check.result == 'success' &&
                  (needs.duplicates-check.result == 'success' || needs.duplicates-check.result == 'skipped') &&
                  (needs.unused-check.result == 'success' || needs.unused-check.result == 'skipped')
            """ : ""

        let stageLabel = includeStaticAnalysis ? "Stage 3" : "Stage 2"

        return """
              # ==========================================================================
              # \(stageLabel): Test with Coverage
              # ==========================================================================
              test:
                name: Test
                runs-on: macos-15\(needsClause)\(ifClause)
                steps:
                  - name: Checkout
                    uses: actions/checkout@v4

                  - name: Select Xcode
                    run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

                  - name: Cache SPM Dependencies
                    uses: actions/cache@v4
                    with:
                      path: .build
                      key: spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
                      restore-keys: spm-${{ runner.os }}-

            \(setupSpkStep())

                  - name: Run CI Hooks
                    run: |
                      ${{ steps.setup-spk.outputs.spk_path }} hooks run ci --fix none

            """
    }

    // swa:ignore-complexity
    static func ciCodeQLJob(needsTest: Bool = true) -> String {
        let needsValue = needsTest ? "test" : "format-check"
        let stageLabel = needsTest ? "Stage 4" : "Stage 3"

        return """
              # ==========================================================================
              # \(stageLabel): Security Analysis
              # ==========================================================================
              codeql:
                name: CodeQL Analysis
                runs-on: macos-15
                needs: \(needsValue)
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

    // swa:ignore-complexity
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
                needs: format-check
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
            entries.append(
                """
                              - platform: iOS
                                destination: 'generic/platform=iOS Simulator'
                """
            )
        }
        if platforms.macOS != nil {
            entries.append(
                """
                              - platform: macOS
                                destination: 'platform=macOS'
                """
            )
        }
        if platforms.tvOS != nil {
            entries.append(
                """
                              - platform: tvOS
                                destination: 'generic/platform=tvOS Simulator'
                """
            )
        }
        if platforms.watchOS != nil {
            entries.append(
                """
                              - platform: watchOS
                                destination: 'generic/platform=watchOS Simulator'
                """
            )
        }
        if platforms.visionOS != nil {
            entries.append(
                """
                              - platform: visionOS
                                destination: 'generic/platform=visionOS Simulator'
                """
            )
        }

        return entries
    }
}

// MARK: - Documentation Jobs

extension DefaultConfigs {
    /// Job that builds documentation using DocC
    /// - Parameters:
    ///   - targetName: The target to generate documentation for
    ///   - hostingBasePath: The base path for static hosting (usually the repo name)
    static func ciDocsJob(targetName: String, hostingBasePath: String) -> String {
        """
          # ==========================================================================
          # Stage 4: Build Documentation
          # ==========================================================================
          docs:
            name: Build Documentation
            runs-on: macos-15
            needs: test
            if: github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v')
            steps:
              - name: Checkout
                uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

              - name: Restore SPM Cache
                uses: actions/cache@v4
                with:
                  path: |
                    .build
                    ~/Library/Developer/Xcode/DerivedData
                  key: spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
                  restore-keys: spm-${{ runner.os }}-

              - name: Build Documentation
                run: |
                  swift package --allow-writing-to-directory ./docs \\
                    generate-documentation \\
                    --target \(targetName) \\
                    --disable-indexing \\
                    --transform-for-static-hosting \\
                    --hosting-base-path \(hostingBasePath) \\
                    --output-path ./docs

              - name: Upload Pages Artifact
                uses: actions/upload-pages-artifact@v3
                with:
                  path: ./docs

        """
    }

    /// Job that deploys documentation to GitHub Pages
    static func ciDeployDocsJob() -> String {
        """
          # ==========================================================================
          # Deploy Documentation
          # ==========================================================================
          deploy-docs:
            name: Deploy Documentation
            runs-on: ubuntu-latest
            needs: docs
            if: github.ref == 'refs/heads/main'
            environment:
              name: github-pages
              url: ${{ steps.deployment.outputs.page_url }}
            steps:
              - name: Deploy to GitHub Pages
                id: deployment
                uses: actions/deploy-pages@v4

        """
    }
}

// MARK: - Release Jobs

extension DefaultConfigs {
    // swa:ignore-complexity
    static func ciPrepareReleaseJob() -> String {
        """
          # ==========================================================================
          # Stage 5: Prepare Release (on tags, manual dispatch, or push to main)
          # ==========================================================================
          prepare-release:
            name: Prepare Release
            runs-on: macos-15
            needs: test
            if: >-
              startsWith(github.ref, 'refs/tags/v') ||
              (github.event_name == 'workflow_dispatch' && inputs.release) ||
              github.event_name == 'push'
            outputs:
              version: ${{ steps.version.outputs.version }}
              tag: ${{ steps.version.outputs.tag }}
              should_release: ${{ steps.version.outputs.should_release }}
              changelog: ${{ steps.changelog.outputs.content }}
            steps:
              - uses: actions/checkout@v4
                with:
                  fetch-depth: 0

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

              - name: Cache SPM Dependencies
                uses: actions/cache@v4
                with:
                  path: .build
                  key: spm-${{ runner.os }}-${{ hashFiles('Package.resolved') }}
                  restore-keys: spm-${{ runner.os }}-

        \(setupSpkStep())

              - name: Determine Version
                id: version
                run: |
                  # Try spk version first, fall back to .spk.json parsing, then VERSION file
                  if VERSION=$(${{ steps.setup-spk.outputs.spk_path }} version --quiet 2>/dev/null); then
                    echo "Got version from spk: ${VERSION}"
                  elif [[ -f ".spk.json" ]] && command -v jq &> /dev/null; then
                    VERSION=$(jq -r '.project.version // empty' .spk.json)
                  elif [[ -f "VERSION" ]]; then
                    VERSION=$(cat VERSION | tr -d '[:space:]')
                  elif [[ -n "${{ inputs.version }}" ]]; then
                    VERSION="${{ inputs.version }}"
                  elif [[ "$GITHUB_REF" == refs/tags/v* ]]; then
                    VERSION="${GITHUB_REF#refs/tags/v}"
                  else
                    echo "No version source found"
                    exit 1
                  fi

                  TAG="v${VERSION}"
                  echo "version=${VERSION}" >> $GITHUB_OUTPUT
                  echo "tag=${TAG}" >> $GITHUB_OUTPUT

                  # Check if this version already has a tag (skip release if so)
                  if git rev-parse "${TAG}" >/dev/null 2>&1; then
                    echo "Tag ${TAG} already exists - skipping release"
                    echo "should_release=false" >> $GITHUB_OUTPUT
                  else
                    echo "New version ${VERSION} - will create release"
                    echo "should_release=true" >> $GITHUB_OUTPUT
                  fi

              - name: Generate Changelog
                id: changelog
                run: |
                  PREVIOUS=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
                  RANGE="${PREVIOUS:+$PREVIOUS..}HEAD"

                  {
                    echo "content<<EOF"

                    # Features
                    FEATURES=$(git log $RANGE --pretty=format:"- %s (%h)" \\
                      --grep="^feat" --grep="^add" --grep="^new" -i 2>/dev/null | head -20 || echo "")
                    if [[ -n "$FEATURES" ]]; then
                      echo "### Features"
                      echo "$FEATURES"
                      echo ""
                    fi

                    # Bug Fixes
                    FIXES=$(git log $RANGE --pretty=format:"- %s (%h)" \\
                      --grep="^fix" -i 2>/dev/null | head -20 || echo "")
                    if [[ -n "$FIXES" ]]; then
                      echo "### Bug Fixes"
                      echo "$FIXES"
                      echo ""
                    fi

                    # Other changes
                    OTHER=$(git log $RANGE --pretty=format:"- %s (%h)" --invert-grep \\
                      --grep="^feat" --grep="^fix" --grep="^add" --grep="^new" -i 2>/dev/null | head -15 || echo "")
                    if [[ -n "$OTHER" ]]; then
                      echo "### Other Changes"
                      echo "$OTHER"
                      echo ""
                    fi

                    echo "EOF"
                  } >> $GITHUB_OUTPUT

        """
    }

    // swa:ignore-complexity
    static func ciCreateReleaseJob(name: String) -> String {
        """
          # ==========================================================================
          # Stage 6: Create GitHub Release (Tags and workflow_dispatch)
          # ==========================================================================
          release:
            name: Create Release
            runs-on: macos-15
            needs: prepare-release
            if: needs.prepare-release.outputs.should_release == 'true'
            steps:
              - uses: actions/checkout@v4

              - name: Create Tag
                if: >-
                  github.event_name == 'workflow_dispatch' ||
                  (github.event_name == 'push' && github.ref == 'refs/heads/main')
                run: |
                  git config user.name "github-actions[bot]"
                  git config user.email "github-actions[bot]@users.noreply.github.com"
                  git tag -a "${{ needs.prepare-release.outputs.tag }}" \\
                    -m "Release ${{ needs.prepare-release.outputs.version }}" || true
                  git push origin "${{ needs.prepare-release.outputs.tag }}" || true

              - name: Prepare Release Notes
                run: |
                  VERSION="${{ needs.prepare-release.outputs.version }}"
                  cat > release_notes.md << 'RELEASE_EOF'
                  # \(name) v${VERSION}

                  ${{ needs.prepare-release.outputs.changelog }}

                  ---

                  ## Installation

                  ### Swift Package Manager

                  ```swift
                  dependencies: [
                      .package(
                          url: "https://github.com/g-cqd/\(name).git",
                          from: "${VERSION}"
                      )
                  ]
                  ```

                  RELEASE_EOF

              - name: Create GitHub Release
                uses: softprops/action-gh-release@v2
                with:
                  tag_name: ${{ needs.prepare-release.outputs.tag }}
                  name: \(name) ${{ needs.prepare-release.outputs.version }}
                  body_path: release_notes.md
                  draft: false
                  prerelease: >-
                    ${{ contains(needs.prepare-release.outputs.version, 'alpha') ||
                        contains(needs.prepare-release.outputs.version, 'beta') ||
                        contains(needs.prepare-release.outputs.version, 'rc') }}
                env:
                  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        """
    }

    // swa:ignore-complexity
    // Creates a release job with universal binary building and packaging for CLI tools
    static func ciCreateBinaryReleaseJob(
        name: String,
        binaryName: String,
        includeHomebrew: Bool = false,
        homebrewTap: String? = nil,
    ) -> String {
        let homebrewInstall =
            if includeHomebrew, let tap = homebrewTap {
                """

                          **Homebrew:**
                          \\`\\`\\`bash
                          brew tap \(tap)
                          brew install \(binaryName)
                          \\`\\`\\`
                """
            } else {
                ""
            }

        let homebrewFormulaStep =
            if includeHomebrew {
                """

                      - name: Generate Homebrew Formula
                        run: |
                          VERSION="${{ needs.prepare-release.outputs.version }}"
                          TAG="${{ needs.prepare-release.outputs.tag }}"

                          # Read checksums
                          ARM64_SHA=$(grep "arm64" release/checksums.txt | awk '{print $1}')
                          X86_SHA=$(grep "x86_64" release/checksums.txt | awk '{print $1}')

                          cat > release/\(binaryName).rb << FORMULA_EOF
                          class \(binaryName.capitalized) < Formula
                            desc "\(name) CLI tool"
                            homepage "https://github.com/g-cqd/\(name)"
                            version "${VERSION}"
                            license "MIT"

                            on_macos do
                              if Hardware::CPU.arm?
                                url "https://github.com/g-cqd/\(name)/releases/download/${TAG}/\(
                                binaryName
                            )-${VERSION}-macos-arm64.tar.gz"
                                sha256 "${ARM64_SHA}"
                              else
                                url "https://github.com/g-cqd/\(name)/releases/download/${TAG}/\(
                                binaryName
                            )-${VERSION}-macos-x86_64.tar.gz"
                                sha256 "${X86_SHA}"
                              end
                            end

                            def install
                              bin.install "\(binaryName)"
                            end

                            test do
                              assert_match version.to_s, shell_output("#{bin}/\(binaryName) --version")
                            end
                          end
                          FORMULA_EOF
                """
            } else {
                ""
            }

        let formulaFile =
            includeHomebrew
            ? """

                    release/\(binaryName).rb
            """ : ""

        return """
              # ==========================================================================
              # Stage 6: Create GitHub Release with Universal Binaries
              # ==========================================================================
              release:
                name: Create Release
                runs-on: macos-15
                needs: prepare-release
                if: needs.prepare-release.outputs.should_release == 'true'
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

                  - name: Build Universal Binary
                    run: |
                      # Build for ARM64
                      swift build -c release --arch arm64
                      cp .build/arm64-apple-macosx/release/\(binaryName) .build/\(binaryName)-arm64

                      # Build for x86_64
                      swift build -c release --arch x86_64
                      cp .build/x86_64-apple-macosx/release/\(binaryName) .build/\(binaryName)-x86_64

                      # Create universal binary
                      mkdir -p .build/release
                      lipo -create -output .build/release/\(binaryName) \\
                        .build/\(binaryName)-arm64 \\
                        .build/\(binaryName)-x86_64

                      lipo -info .build/release/\(binaryName)

                  - name: Package Binaries
                    run: |
                      VERSION="${{ needs.prepare-release.outputs.version }}"
                      mkdir -p release

                      for ARCH in universal arm64 x86_64; do
                        if [[ "$ARCH" == "universal" ]]; then
                          cp .build/release/\(binaryName) release/\(binaryName)
                        else
                          cp .build/\(binaryName)-$ARCH release/\(binaryName)
                        fi
                        tar -C release -czvf "release/\(binaryName)-${VERSION}-macos-${ARCH}.tar.gz" \(binaryName)
                      done

                      cd release && shasum -a 256 *.tar.gz > checksums.txt
            \(homebrewFormulaStep)

                  - name: Create Tag
                    if: >-
                      github.event_name == 'workflow_dispatch' ||
                      (github.event_name == 'push' && github.ref == 'refs/heads/main')
                    run: |
                      git config user.name "github-actions[bot]"
                      git config user.email "github-actions[bot]@users.noreply.github.com"
                      git tag -a "${{ needs.prepare-release.outputs.tag }}" \\
                        -m "Release ${{ needs.prepare-release.outputs.version }}" || true
                      git push origin "${{ needs.prepare-release.outputs.tag }}" || true

                  - name: Prepare Release Notes
                    run: |
                      VERSION="${{ needs.prepare-release.outputs.version }}"
                      TAG="${{ needs.prepare-release.outputs.tag }}"
                      cat > release_notes.md << RELEASE_EOF
                      # \(name) v${VERSION}

                      ${{ needs.prepare-release.outputs.changelog }}

                      ---

                      ## Installation
            \(homebrewInstall)
                      **Swift Package Manager:**
                      \\`\\`\\`swift
                      dependencies: [
                          .package(url: "https://github.com/g-cqd/\(name).git", from: "${VERSION}")
                      ]
                      \\`\\`\\`

                      **Pre-built Binary (macOS):**
                      \\`\\`\\`bash
                      # Universal (Apple Silicon + Intel)
                      curl -L https://github.com/g-cqd/\(name)/releases/download/${TAG}/\(
                      binaryName
                  )-${VERSION}-macos-universal.tar.gz | tar xz
                      sudo mv \(binaryName) /usr/local/bin/
                      \\`\\`\\`

                      ### Checksums

                      \\`\\`\\`
                      $(cat release/checksums.txt)
                      \\`\\`\\`

                      RELEASE_EOF

                  - name: Create GitHub Release
                    uses: softprops/action-gh-release@v2
                    with:
                      tag_name: ${{ needs.prepare-release.outputs.tag }}
                      name: \(name) ${{ needs.prepare-release.outputs.version }}
                      body_path: release_notes.md
                      draft: false
                      prerelease: >-
                        ${{ contains(needs.prepare-release.outputs.version, 'alpha') ||
                            contains(needs.prepare-release.outputs.version, 'beta') ||
                            contains(needs.prepare-release.outputs.version, 'rc') }}
                      files: |
                        release/\(binaryName)-${{ needs.prepare-release.outputs.version }}-macos-*.tar.gz
                        release/checksums.txt\(formulaFile)
                    env:
                      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
            """
    }
}

// swa:ignore-file-length
// Template files benefit from keeping related templates together
import Foundation

// MARK: - Unified CI/CD Workflow

extension DefaultConfigs {
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
    ) -> String {
        let resolvedBinaryName = binaryName ?? name.lowercased()

        var workflow = ciWorkflowHeader(includeRelease: includeRelease)
        workflow += ciLintJob()
        workflow += ciBuildAndTestJob()
        workflow += ciCodeQLJob()

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

        return workflow
    }
}

// MARK: - Workflow Header

extension DefaultConfigs {
    // swa:ignore-complexity
    static func ciWorkflowHeader(includeRelease: Bool) -> String {
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

        let permissions =
            includeRelease
            ? """
            permissions:
              contents: write
              security-events: write
            """
            : """
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
          format-check:
            name: Format Check
            runs-on: macos-15
            steps:
              - uses: actions/checkout@v4

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_${{ env.XCODE_VERSION }}.app

              - name: Check Formatting
                run: xcrun swift-format lint --strict --recursive .

        """
    }

    static func ciBuildAndTestJob() -> String {
        """
          # ==========================================================================
          # Stage 2: Build & Test (Always runs, depends on format check)
          # ==========================================================================
          build-and-test:
            name: Build & Test
            runs-on: macos-15
            needs: format-check
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

              - name: Build
                run: swift build -c release

              - name: Run Tests
                run: swift test --parallel

        """
    }

    // swa:ignore-complexity
    static func ciCodeQLJob() -> String {
        """
          # ==========================================================================
          # Stage 3: Security Analysis (Always runs, depends on format check)
          # ==========================================================================
          codeql:
            name: CodeQL Analysis
            runs-on: macos-15
            needs: format-check
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
            runs-on: ubuntu-latest
            needs: build-and-test
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

              - name: Determine Version
                id: version
                run: |
                  # Read version from VERSION file (single source of truth)
                  if [[ -f "VERSION" ]]; then
                    VERSION=$(cat VERSION | tr -d '[:space:]')
                  elif [[ -n "${{ inputs.version }}" ]]; then
                    VERSION="${{ inputs.version }}"
                  elif [[ "$GITHUB_REF" == refs/tags/v* ]]; then
                    VERSION="${GITHUB_REF#refs/tags/v}"
                  else
                    echo "No VERSION file found and no version specified"
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

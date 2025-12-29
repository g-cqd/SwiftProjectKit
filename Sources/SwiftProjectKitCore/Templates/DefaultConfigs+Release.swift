import Foundation

// MARK: - Release Workflow

public extension DefaultConfigs {
    static func releaseWorkflow(name: String) -> String {
        var workflow = releaseWorkflowHeader()
        workflow += releaseValidateJob()
        workflow += releaseChangelogJob()
        workflow += releaseCreateReleaseJob(name: name)
        return workflow
    }
}

// MARK: - Release Workflow Components

extension DefaultConfigs {
    static func releaseWorkflowHeader() -> String {
        """
        name: Release

        on:
          push:
            tags:
              - 'v*'
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

        permissions:
          contents: write

        concurrency:
          group: release-${{ github.ref }}
          cancel-in-progress: true

        jobs:
        """
    }

    static func releaseValidateJob() -> String {
        """

          validate:
            name: Validate
            runs-on: macos-15
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
                  else
                    VERSION="${GITHUB_REF#refs/tags/v}"
                  fi
                  echo "version=$VERSION" >> $GITHUB_OUTPUT
                  echo "Releasing version: $VERSION"

              - name: Get Previous Tag
                id: previous
                run: |
                  PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
                  echo "tag=$PREV_TAG" >> $GITHUB_OUTPUT

              - name: Select Xcode
                run: sudo xcode-select -s /Applications/Xcode_26.1.1.app

              - name: Build
                run: swift build -c release

              - name: Run Tests
                run: swift test --parallel

        """
    }

    static func releaseChangelogJob() -> String {
        """
          changelog:
            name: Generate Changelog
            runs-on: ubuntu-latest
            needs: validate
            outputs:
              changelog: ${{ steps.generate.outputs.changelog }}
            steps:
              - uses: actions/checkout@v4
                with:
                  fetch-depth: 0

              - name: Generate Changelog
                id: generate
                run: |
                  PREV_TAG="${{ needs.validate.outputs.previous_tag }}"
                  VERSION="${{ needs.validate.outputs.version }}"

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
    static func releaseCreateReleaseJob(name: String) -> String {
        """
          create-release:
            name: Create Release
            runs-on: macos-15
            needs: [validate, changelog]
            steps:
              - uses: actions/checkout@v4

              - name: Create Tag (if workflow_dispatch)
                if: github.event_name == 'workflow_dispatch' && inputs.create_tag
                run: |
                  git config user.name "github-actions[bot]"
                  git config user.email "github-actions[bot]@users.noreply.github.com"
                  git tag -a "v${{ needs.validate.outputs.version }}" \\
                    -m "Release v${{ needs.validate.outputs.version }}"
                  git push origin "v${{ needs.validate.outputs.version }}"

              - name: Prepare Release Notes
                run: |
                  cat > release_notes.md << 'RELEASE_EOF'
                  # \(name) v${{ needs.validate.outputs.version }}

                  ${{ needs.changelog.outputs.changelog }}

                  ---

                  ## Installation

                  ### Swift Package Manager

                  ```swift
                  dependencies: [
                      .package(
                          url: "https://github.com/g-cqd/\(name).git",
                          from: "${{ needs.validate.outputs.version }}"
                      )
                  ]
                  ```

                  RELEASE_EOF

              - name: Create GitHub Release
                uses: softprops/action-gh-release@v2
                with:
                  tag_name: v${{ needs.validate.outputs.version }}
                  name: \(name) v${{ needs.validate.outputs.version }}
                  body_path: release_notes.md
                  draft: false
                  prerelease: ${{ \
        contains(needs.validate.outputs.version, 'alpha') || \
        contains(needs.validate.outputs.version, 'beta') || \
        contains(needs.validate.outputs.version, 'rc') \
        }}
                env:
                  GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        """
    }
    // swiftlint:enable function_body_length
}

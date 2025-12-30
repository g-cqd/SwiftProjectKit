#!/bin/bash
#
# Check version consistency across all files
#
# This script ensures the version number is consistent across:
# - VERSION file
# - Sources/SwiftProjectKitCore/SwiftProjectKitCore.swift
# - README.md (if versioned)
#
# Usage: ./scripts/check-version.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get version from VERSION file (single source of truth)
if [ ! -f "VERSION" ]; then
    echo -e "${RED}ERROR: VERSION file not found${NC}"
    exit 1
fi

VERSION=$(cat VERSION | tr -d '[:space:]')

if [ -z "$VERSION" ]; then
    echo -e "${RED}ERROR: VERSION file is empty${NC}"
    exit 1
fi

echo "Checking version consistency (expected: $VERSION)..."

ERRORS=0

# Check SwiftProjectKitCore.swift
CORE_VERSION=$(grep -oE 'swiftProjectKitVersion = "[0-9]+\.[0-9]+\.[0-9]+"' Sources/SwiftProjectKitCore/SwiftProjectKitCore.swift | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "NOT_FOUND")
if [ "$CORE_VERSION" != "$VERSION" ]; then
    echo -e "${RED}MISMATCH: Sources/SwiftProjectKitCore/SwiftProjectKitCore.swift has version '$CORE_VERSION'${NC}"
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}OK: Sources/SwiftProjectKitCore/SwiftProjectKitCore.swift${NC}"
fi

# Check README.md SPM dependency version (if present)
README_VERSION=$(grep -oE 'from: "[0-9]+\.[0-9]+\.[0-9]+"' README.md 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "NOT_FOUND")
if [ "$README_VERSION" != "NOT_FOUND" ] && [ "$README_VERSION" != "$VERSION" ]; then
    echo -e "${YELLOW}WARNING: README.md has version '$README_VERSION' (may be intentional)${NC}"
else
    echo -e "${GREEN}OK: README.md${NC}"
fi

# Check CHANGELOG.md has entry for this version (warning only)
if [ -f "CHANGELOG.md" ]; then
    if ! grep -q "## \[$VERSION\]" CHANGELOG.md && ! grep -q "## $VERSION" CHANGELOG.md; then
        echo -e "${YELLOW}WARNING: CHANGELOG.md missing entry for version $VERSION${NC}"
    else
        echo -e "${GREEN}OK: CHANGELOG.md${NC}"
    fi
fi

if [ $ERRORS -gt 0 ]; then
    echo -e "\n${RED}Version check failed with $ERRORS error(s)${NC}"
    echo -e "To fix, update the version in:"
    echo -e "  - Sources/SwiftProjectKitCore/SwiftProjectKitCore.swift"
    exit 1
fi

echo -e "\n${GREEN}Version check passed! All files have version $VERSION${NC}"
exit 0

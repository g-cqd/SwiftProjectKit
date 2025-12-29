#!/bin/bash
# SwiftFormat & SwiftLint Test Runner
# Runs both tools against fixture files to demonstrate behavior

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/../Fixtures"
PROJECT_ROOT="$SCRIPT_DIR/../.."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}SwiftFormat & SwiftLint Test Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if tools are installed
check_tool() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 found: $(command -v "$1")"
        return 0
    else
        echo -e "${RED}✗${NC} $1 not found"
        return 1
    fi
}

echo -e "${YELLOW}Checking tools...${NC}"
SWIFTFORMAT_OK=false
SWIFTLINT_OK=false

if check_tool swiftformat; then
    SWIFTFORMAT_OK=true
    echo "  Version: $(swiftformat --version)"
fi

if check_tool swiftlint; then
    SWIFTLINT_OK=true
    echo "  Version: $(swiftlint version)"
fi

echo ""

# Function to run SwiftFormat lint on a file
run_swiftformat() {
    local file="$1"
    local filename=$(basename "$file")

    echo -e "${BLUE}─────────────────────────────────────────${NC}"
    echo -e "${BLUE}SwiftFormat: $filename${NC}"
    echo -e "${BLUE}─────────────────────────────────────────${NC}"

    # Use project's .swiftformat config
    if swiftformat --lint "$file" --config "$PROJECT_ROOT/.swiftformat" 2>&1; then
        echo -e "${GREEN}✓ No formatting issues${NC}"
    else
        echo -e "${YELLOW}⚠ Formatting issues found (above)${NC}"
    fi
    echo ""
}

# Function to run SwiftLint on a file
run_swiftlint() {
    local file="$1"
    local filename=$(basename "$file")

    echo -e "${BLUE}─────────────────────────────────────────${NC}"
    echo -e "${BLUE}SwiftLint: $filename${NC}"
    echo -e "${BLUE}─────────────────────────────────────────${NC}"

    # Use project's .swiftlint.yml config
    if swiftlint lint "$file" --config "$PROJECT_ROOT/.swiftlint.yml" --quiet 2>&1; then
        echo -e "${GREEN}✓ No lint issues${NC}"
    else
        echo -e "${YELLOW}⚠ Lint issues found (above)${NC}"
    fi
    echo ""
}

# Run tests on all fixture files
echo -e "${YELLOW}Running tests on fixture files...${NC}"
echo ""

for fixture in "$FIXTURES_DIR"/*.swift; do
    if [ -f "$fixture" ]; then
        if [ "$SWIFTFORMAT_OK" = true ]; then
            run_swiftformat "$fixture"
        fi
        if [ "$SWIFTLINT_OK" = true ]; then
            run_swiftlint "$fixture"
        fi
    fi
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test run complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Review the output above to see:"
echo "1. Which rules trigger on each fixture"
echo "2. How SwiftFormat and SwiftLint differ in behavior"
echo "3. Where conflicts might occur"
echo ""
echo "To auto-fix issues:"
echo "  swiftformat LintFormatTests/Fixtures/"
echo "  swiftlint lint --fix LintFormatTests/Fixtures/"

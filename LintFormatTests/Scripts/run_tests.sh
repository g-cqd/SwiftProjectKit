#!/bin/bash
# swift-format Test Runner
# Runs format checks on fixture files

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
echo -e "${BLUE}swift-format Test Runner${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if swift-format is available via xcrun
echo -e "${YELLOW}Checking swift-format...${NC}"
if xcrun swift-format --version &> /dev/null; then
    echo -e "${GREEN}✓${NC} swift-format found (via xcrun)"
    echo "  Version: $(xcrun swift-format --version)"
else
    echo -e "${RED}✗${NC} swift-format not found"
    echo "  Make sure Xcode is installed and xcode-select is configured"
    exit 1
fi
echo ""

# Function to run swift-format lint on a file
run_format_check() {
    local file="$1"
    local filename=$(basename "$file")

    # Skip files with swift-format-ignore-file
    if grep -q "swift-format-ignore-file" "$file" 2>/dev/null; then
        echo -e "${YELLOW}⊘${NC} $filename (ignored via swift-format-ignore-file)"
        return 0
    fi

    echo -e "${BLUE}─────────────────────────────────────────${NC}"
    echo -e "${BLUE}Checking: $filename${NC}"
    echo -e "${BLUE}─────────────────────────────────────────${NC}"

    # Use project's .swift-format config
    if xcrun swift-format lint --strict "$file" --configuration "$PROJECT_ROOT/.swift-format" 2>&1; then
        echo -e "${GREEN}✓ No formatting issues${NC}"
    else
        echo -e "${YELLOW}⚠ Formatting issues found (above)${NC}"
    fi
    echo ""
}

# Run tests on all fixture files
echo -e "${YELLOW}Running format checks on fixture files...${NC}"
echo ""

for fixture in "$FIXTURES_DIR"/*.swift; do
    if [ -f "$fixture" ]; then
        run_format_check "$fixture"
    fi
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test run complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "To auto-fix issues:"
echo "  xcrun swift-format format --in-place --recursive LintFormatTests/Fixtures/"
echo ""

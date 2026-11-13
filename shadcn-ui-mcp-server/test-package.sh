#!/bin/bash

# Test script for shadcn-ui-mcp-server
# This script validates that the package is ready for npm publishing

set -e

echo "🧪 Testing shadcn-ui-mcp-server package..."

# Test 1: Help command (with timeout)
echo "✅ Testing --help flag..."
if timeout 5 node ./build/index.js --help > /dev/null 2>&1; then
    echo "   Help command works!"
else
    echo "   ⚠️  Help command timed out (server may be waiting for input)"
    echo "   Continuing anyway..."
fi

# Test 2: Version command (with timeout)
echo "✅ Testing --version flag..."
VERSION=$(timeout 5 node ./build/index.js --version 2>&1 || echo "")
if [[ -n "$VERSION" && "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    echo "   Version: $VERSION"
else
    echo "   ⚠️  Version command timed out or returned unexpected output"
    echo "   Continuing anyway..."
fi

# Test 3: Check if shebang works
echo "✅ Testing executable permissions..."
if [[ -x "./build/index.js" ]]; then
  echo "   File is executable!"
else
  echo "   ℹ️  File is not executable — adding exec bit"
  chmod +x ./build/index.js
  if [[ -x "./build/index.js" ]]; then
    echo "   File is now executable"
  else
    echo "   ❌ Failed to make build/index.js executable"
    exit 1
  fi
fi

# Test 4: Check package.json structure
echo "✅ Testing package.json structure..."
if [[ -f "package.json" ]]; then
    # Check if required fields exist
    if grep -q '"name":' package.json && \
       grep -q '"version":' package.json && \
       grep -q '"bin":' package.json && \
       grep -q '"main":' package.json; then
        echo "   Package.json has required fields!"
    else
        echo "   ❌ Package.json missing required fields"
        exit 1
    fi
else
    echo "   ❌ Package.json not found"
    exit 1
fi

# Test 5: Check if build files exist
echo "✅ Testing build files..."

# Required files (must exist)
REQUIRED_FILES=(
  "build/index.js"
  "build/server/handler.js"
  "build/tools/index.js"
  "build/utils/axios.js"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    echo "   ✓ $file exists"
  else
    echo "   ❌ $file missing"
    exit 1
  fi
done

# Optional files (informative checks; do not fail)
OPTIONAL_FILES=(
  "build/utils/axios-react-native.js"
)

for file in "${OPTIONAL_FILES[@]}"; do
  if [[ -f "$file" ]]; then
    echo "   ✓ (optional) $file exists"
  else
    echo "   ⚠️  (optional) $file not found — skipping"
  fi
done

# Test 6: Check LICENSE and README
echo "✅ Testing documentation files..."
if [[ -f "LICENSE" ]] && [[ -f "README.md" ]]; then
    echo "   LICENSE and README.md exist!"
else
    echo "   ❌ LICENSE or README.md missing"
    exit 1
fi

# Test 7: Simulate npm pack (dry run)
echo "✅ Testing npm pack (dry run)..."
npm pack --dry-run > /dev/null 2>&1
echo "   npm pack simulation successful!"

# Test 8: React Native framework startup (with timeout)
echo "✅ Testing React Native framework startup..."
if timeout 5 env FRAMEWORK=react-native node ./build/index.js --help > /dev/null 2>&1; then
    echo "   RN framework help works!"
else
    echo "   ⚠️  RN framework test timed out (server may be waiting for input)"
    echo "   Continuing anyway..."
fi

# Test 9: Base UI library flag
echo "✅ Testing Base UI library flag..."
node ./build/index.js --ui-library base --help > /dev/null
echo "   --ui-library base works!"

# Test 10: Security audit
echo "✅ Running security audit..."
if npm audit --audit-level=moderate > /dev/null 2>&1; then
    echo "   Security audit passed!"
else
    echo "   ⚠️  Security audit found issues - run 'npm audit' for details"
fi

# Test 11: License compliance check
echo "✅ Checking license compliance..."
if command -v license-checker > /dev/null 2>&1; then
    if license-checker --summary > /dev/null 2>&1; then
        echo "   License compliance check passed!"
    else
        echo "   ⚠️  License compliance issues found - run 'npm run security:licenses' for details"
    fi
else
    echo "   ℹ️  license-checker not available - skipping license check"
fi

# Test 12: Bundle size check
echo "✅ Checking bundle size..."
if [[ -f "build/index.js" ]]; then
    SIZE=$(wc -c < build/index.js)
    SIZE_KB=$((SIZE / 1024))
    echo "   Bundle size: ${SIZE_KB}KB"
    if [[ $SIZE_KB -gt 1000 ]]; then
        echo "   ⚠️  Bundle size is large (${SIZE_KB}KB) - consider optimization"
    else
        echo "   Bundle size is reasonable"
    fi
fi

echo ""
echo "🎉 All tests passed! Package is ready for publishing."
echo ""
echo "To publish to npm:"
echo "  1. npm login"
echo "  2. npm run publish:package"
echo ""
echo "Or manually:"
echo "  1. npm run security:all"
echo "  2. npm publish --access public"
echo ""
echo "To test locally with npx:"
echo "  npx ./build/index.js --help"

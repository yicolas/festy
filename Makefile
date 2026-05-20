# FestMest Makefile
# Field trip companion app built on bitchat mesh networking
#
# Uses Config/project.json for project settings and test matrix

.PHONY: all build test test-parallel test-matrix lint format check clean help

# ============================================================================
# Configuration
# ============================================================================

# Project settings (from Config/project.json)
PROJECT := FestMest.xcodeproj
SCHEME_IOS := FestMest (iOS)
SCHEME_MACOS := FestMest (macOS)

# Code signing (disabled for CI)
CODESIGN_FLAGS := CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=""

# Default target
all: check build test

# ============================================================================
# Build Commands
# ============================================================================

## Build the Swift package
build:
	@echo "🔨 Building Swift package..."
	swift build

## Build for release
build-release:
	@echo "🔨 Building release..."
	swift build -c release

## Build iOS app (requires Xcode)
build-ios:
	@echo "📱 Building FestMest iOS..."
	xcodebuild -project $(PROJECT) \
		-scheme "$(SCHEME_IOS)" \
		-destination "generic/platform=iOS" \
		-configuration Debug \
		$(CODESIGN_FLAGS) \
		build

## Build macOS app (requires Xcode)
build-macos:
	@echo "🖥️  Building FestMest macOS..."
	xcodebuild -project $(PROJECT) \
		-scheme "$(SCHEME_MACOS)" \
		-configuration Debug \
		$(CODESIGN_FLAGS) \
		build

# ============================================================================
# Test Commands
# ============================================================================

## Run all tests (SPM)
test:
	@echo "🧪 Running tests..."
	swift test

## Run tests in parallel (SPM)
test-parallel:
	@echo "🧪 Running tests in parallel..."
	swift test --parallel

## Run tests with verbose output
test-verbose:
	@echo "🧪 Running tests (verbose)..."
	swift test --verbose

## Run specific test file (usage: make test-file FILE=TripGroupTests)
test-file:
	@echo "🧪 Running tests matching: $(FILE)..."
	swift test --filter $(FILE)

## Run trip group tests only
test-groups:
	@echo "🧪 Running trip group tests..."
	swift test --filter TripGroup

## Run trip feature tests only
test-trip:
	@echo "🧪 Running trip feature tests..."
	swift test --filter Trip

## Run iOS simulator test matrix (reads from Config/project.json)
test-matrix:
	@echo "🧪 Running iOS simulator test matrix..."
	@./scripts/run-test-matrix.sh

## Run tests on a specific iOS simulator
## Usage: make test-ios-sim SIMULATOR="iPhone 15 Pro"
test-ios-sim:
	@echo "🧪 Testing on $(SIMULATOR)..."
	xcodebuild test \
		-project $(PROJECT) \
		-scheme "$(SCHEME_IOS)" \
		-destination "platform=iOS Simulator,name=$(SIMULATOR)" \
		$(CODESIGN_FLAGS) \
		-only-testing:bitchatTests

## Run tests on default simulator (iPhone 15 Pro)
test-ios:
	@$(MAKE) test-ios-sim SIMULATOR="iPhone 15 Pro"

## Run tests with code coverage
test-coverage:
	@echo "🧪 Running tests with coverage..."
	xcodebuild test \
		-project $(PROJECT) \
		-scheme "$(SCHEME_IOS)" \
		-destination "platform=iOS Simulator,name=iPhone 15 Pro" \
		-enableCodeCoverage YES \
		$(CODESIGN_FLAGS)

# ============================================================================
# Code Quality Commands
# ============================================================================

## Run SwiftLint (if installed)
lint:
	@echo "🔍 Running SwiftLint..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --quiet; \
	else \
		echo "⚠️  SwiftLint not installed. Install with: brew install swiftlint"; \
		exit 0; \
	fi

## Run SwiftLint and auto-fix issues
lint-fix:
	@echo "🔧 Running SwiftLint with auto-fix..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --fix --quiet; \
	else \
		echo "⚠️  SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

## Format code with swift-format (if installed)
format:
	@echo "✨ Formatting code..."
	@if command -v swift-format >/dev/null 2>&1; then \
		find bitchat bitchatTests -name "*.swift" -exec swift-format -i {} \;; \
	else \
		echo "⚠️  swift-format not installed. Install with: brew install swift-format"; \
		exit 0; \
	fi

## Check formatting without modifying files
format-check:
	@echo "🔍 Checking code formatting..."
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format lint -r bitchat bitchatTests; \
	else \
		echo "⚠️  swift-format not installed. Install with: brew install swift-format"; \
		exit 0; \
	fi

# ============================================================================
# Pre-commit / CI Checks
# ============================================================================

## Run all checks (build + test + lint)
check: build test lint
	@echo "✅ All checks passed!"

## Quick check (build + fast tests only)
check-quick: build
	@echo "🧪 Running quick tests..."
	swift test --filter "ModelTests|IdTests|SignableDataTests"
	@echo "✅ Quick checks passed!"

## CI check (what runs in GitHub Actions)
ci:
	@echo "🤖 Running CI checks..."
	@echo "Step 1/3: Building..."
	swift build
	@echo "Step 2/3: Running tests..."
	swift test --parallel
	@echo "Step 3/3: Linting..."
	@$(MAKE) lint || true
	@echo "✅ CI checks complete!"

# ============================================================================
# Utility Commands
# ============================================================================

## Clean build artifacts
clean:
	@echo "🧹 Cleaning..."
	swift package clean
	rm -rf .build
	rm -rf ~/Library/Developer/Xcode/DerivedData/FestMest-* 2>/dev/null || true
	rm -rf ~/Library/Developer/Xcode/DerivedData/bitchat-* 2>/dev/null || true

## Deep clean including Xcode derived data
clean-all: clean
	@echo "🧹 Deep cleaning..."
	rm -rf ~/Library/Developer/Xcode/DerivedData/*

## Show package dependencies
deps:
	@echo "📦 Package dependencies:"
	swift package show-dependencies

## Update package dependencies
deps-update:
	@echo "📦 Updating dependencies..."
	swift package update

## List available iOS simulators
list-simulators:
	@echo "📱 Available iOS Simulators:"
	@xcrun simctl list devices available | grep -E "iPhone|iPad"

## Show test matrix configuration
show-matrix:
	@echo "📋 Test Matrix Configuration:"
	@cat Config/project.json | python3 -c "import json,sys; c=json.load(sys.stdin); print('\n'.join([f\"  {s['name']} (iOS {s['os_version']}) {'✓' if s['enabled'] else '✗'}\" for s in c['test_matrix']['ios_simulators']]))"

# ============================================================================
# Development Helpers
# ============================================================================

## Run the macOS app (builds first)
run: build-macos
	@echo "🚀 Launching FestMest..."
	@find ~/Library/Developer/Xcode/DerivedData -name "FestMest.app" -path "*/Debug/*" -not -path "*/Index.noindex/*" | head -1 | xargs -I {} open "{}"

## Watch for changes and run tests (requires fswatch)
watch:
	@echo "👀 Watching for changes..."
	@if command -v fswatch >/dev/null 2>&1; then \
		fswatch -o bitchat bitchatTests | xargs -n1 -I{} make test; \
	else \
		echo "⚠️  fswatch not installed. Install with: brew install fswatch"; \
	fi

## Open project in Xcode
xcode:
	@echo "🔵 Opening FestMest in Xcode..."
	open $(PROJECT)

# ============================================================================
# Help
# ============================================================================

## Show this help
help:
	@echo "FestMest - Field Trip Companion App"
	@echo "================================="
	@echo "Built on bitchat mesh networking protocol"
	@echo ""
	@echo "Build:"
	@echo "  make build          - Build Swift package"
	@echo "  make build-release  - Build for release"
	@echo "  make build-ios      - Build iOS app"
	@echo "  make build-macos    - Build macOS app"
	@echo ""
	@echo "Test:"
	@echo "  make test           - Run all tests (SPM)"
	@echo "  make test-parallel  - Run tests in parallel"
	@echo "  make test-ios       - Run tests on iOS simulator"
	@echo "  make test-matrix    - Run full iOS simulator matrix"
	@echo "  make test-groups    - Run trip group tests"
	@echo "  make test-coverage  - Run tests with coverage"
	@echo ""
	@echo "Code Quality:"
	@echo "  make lint           - Run SwiftLint"
	@echo "  make lint-fix       - Auto-fix lint issues"
	@echo "  make format         - Format code"
	@echo ""
	@echo "CI/Checks:"
	@echo "  make check          - Run all checks"
	@echo "  make ci             - Full CI pipeline"
	@echo ""
	@echo "Utility:"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make list-simulators- List available simulators"
	@echo "  make show-matrix    - Show test matrix config"
	@echo "  make run            - Build and run macOS app"
	@echo "  make xcode          - Open in Xcode"
	@echo ""

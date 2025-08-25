# Makefile for unwarp test harness
# Provides build automation and test execution targets

# Variables
PROJECT_ROOT := ..
TEST_DIR := .
BIN_DIR := $(TEST_DIR)/bin
OUTPUT_DIR := $(TEST_DIR)/output
MOCK_DIR := $(TEST_DIR)/mocks
SOURCE := $(PROJECT_ROOT)/unwarp.m
TEST_BINARY := $(BIN_DIR)/unwarp_test
PROD_BINARY := $(PROJECT_ROOT)/unwarp

# Compiler settings
CC := clang
FRAMEWORKS := -framework Foundation \
              -framework LocalAuthentication \
              -framework Security \
              -framework SystemConfiguration
              
CFLAGS := -fobjc-arc -O0 -g
PROD_FLAGS := -fobjc-arc -O2

# Warning flags
WARNINGS := -Weverything \
            -Wno-padded \
            -Wno-gnu-statement-expression \
            -Wno-poison-system-directories \
            -Wno-declaration-after-statement

# Version for test builds
TEST_VERSION := test-$(shell date +%Y%m%d-%H%M%S)

# Color output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# Default target
.PHONY: all
all: help

# Help target
.PHONY: help
help:
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║           UNWARP TEST HARNESS - MAKEFILE                  ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Available targets:"
	@echo "  make test          - Run all tests"
	@echo "  make test-quick    - Run required tests only (skip acceptance)"
	@echo "  make test-unit     - Run unit tests only"
	@echo "  make test-security - Run security tests only"
	@echo "  make test-integration - Run integration tests only"
	@echo "  make test-acceptance - Run acceptance tests only"
	@echo ""
	@echo "  make build         - Build test binary"
	@echo "  make build-prod    - Build production binary"
	@echo "  make clean         - Clean test artifacts"
	@echo "  make distclean     - Clean all artifacts including binaries"
	@echo ""
	@echo "  make check         - Check prerequisites"
	@echo "  make install-deps  - Install test dependencies (if any)"
	@echo ""

# Check prerequisites
.PHONY: check
check:
	@echo "Checking prerequisites..."
	@which clang > /dev/null || (echo "$(RED)ERROR: clang not found$(NC)" && exit 1)
	@which otool > /dev/null || echo "$(YELLOW)WARNING: otool not found (some tests may fail)$(NC)"
	@which plutil > /dev/null || echo "$(YELLOW)WARNING: plutil not found (plist validation unavailable)$(NC)"
	@test -f $(SOURCE) || (echo "$(RED)ERROR: Source file not found: $(SOURCE)$(NC)" && exit 1)
	@echo "$(GREEN)Prerequisites OK$(NC)"

# Build test binary (without setuid)
.PHONY: build
build: check
	@echo "Building test binary (without setuid)..."
	@mkdir -p $(BIN_DIR)
	@$(CC) $(FRAMEWORKS) $(CFLAGS) \
		-DUNWARP_VERSION=\"$(TEST_VERSION)\" \
		$(WARNINGS) \
		-o $(TEST_BINARY) \
		$(SOURCE)
	@if [ $$? -eq 0 ]; then \
		echo "$(GREEN)Test binary built successfully: $(TEST_BINARY)$(NC)"; \
	else \
		echo "$(RED)Build failed$(NC)"; \
		exit 1; \
	fi

# Build production binary
.PHONY: build-prod
build-prod: check
	@echo "Building production binary..."
	@cd $(PROJECT_ROOT) && ./build.sh
	@if [ $$? -eq 0 ]; then \
		echo "$(GREEN)Production binary built successfully: $(PROD_BINARY)$(NC)"; \
	else \
		echo "$(RED)Production build failed$(NC)"; \
		exit 1; \
	fi

# Run all tests
.PHONY: test
test: build
	@echo "Running full test suite..."
	@chmod +x $(TEST_DIR)/test_runner.sh
	@$(TEST_DIR)/test_runner.sh

# Run quick tests (skip optional)
.PHONY: test-quick
test-quick: build
	@echo "Running quick test suite (required tests only)..."
	@chmod +x $(TEST_DIR)/test_runner.sh
	@$(TEST_DIR)/test_runner.sh --quick

# Run unit tests only
.PHONY: test-unit
test-unit: build
	@echo "Running unit tests..."
	@chmod +x $(TEST_DIR)/test_runner.sh
	@$(TEST_DIR)/test_runner.sh --suite unit

# Run security tests only
.PHONY: test-security
test-security: build
	@echo "Running security tests..."
	@chmod +x $(TEST_DIR)/test_runner.sh
	@$(TEST_DIR)/test_runner.sh --suite security

# Run integration tests only
.PHONY: test-integration
test-integration: build
	@echo "Running integration tests..."
	@chmod +x $(TEST_DIR)/test_runner.sh
	@$(TEST_DIR)/test_runner.sh --suite integration

# Run acceptance tests only
.PHONY: test-acceptance
test-acceptance: build
	@echo "Running acceptance tests..."
	@chmod +x $(TEST_DIR)/test_runner.sh
	@$(TEST_DIR)/test_runner.sh --suite acceptance

# Run tests in non-interactive mode
.PHONY: test-ci
test-ci: build
	@echo "Running tests in CI mode (non-interactive)..."
	@chmod +x $(TEST_DIR)/test_runner.sh
	@$(TEST_DIR)/test_runner.sh --non-interactive --quick

# Clean test artifacts
.PHONY: clean
clean:
	@echo "Cleaning test artifacts..."
	@rm -rf $(OUTPUT_DIR)
	@rm -rf $(MOCK_DIR)
	@rm -rf $(BIN_DIR)
	@rm -f $(TEST_DIR)/*.log
	@echo "$(GREEN)Test artifacts cleaned$(NC)"

# Clean all artifacts including binaries
.PHONY: distclean
distclean: clean
	@echo "Cleaning all artifacts..."
	@rm -f $(PROD_BINARY)
	@echo "$(GREEN)All artifacts cleaned$(NC)"

# Install test dependencies (placeholder)
.PHONY: install-deps
install-deps:
	@echo "No external dependencies required for test harness"
	@echo "All tests use standard macOS tools"

# Make test scripts executable
.PHONY: setup
setup:
	@echo "Setting up test harness..."
	@chmod +x $(TEST_DIR)/*.sh
	@echo "$(GREEN)Test harness setup complete$(NC)"

# Run tests with verbose output
.PHONY: test-verbose
test-verbose: build
	@echo "Running tests with verbose output..."
	@chmod +x $(TEST_DIR)/test_runner.sh
	@$(TEST_DIR)/test_runner.sh --verbose

# Generate test report (placeholder for future enhancement)
.PHONY: report
report:
	@echo "Test reporting not yet implemented"
	@echo "Check $(TEST_DIR)/output/ for test logs"

# Validate test harness integrity
.PHONY: validate
validate:
	@echo "Validating test harness..."
	@test -f $(TEST_DIR)/test_helpers.sh || (echo "$(RED)Missing: test_helpers.sh$(NC)" && exit 1)
	@test -f $(TEST_DIR)/unit_tests.sh || (echo "$(RED)Missing: unit_tests.sh$(NC)" && exit 1)
	@test -f $(TEST_DIR)/security_tests.sh || (echo "$(RED)Missing: security_tests.sh$(NC)" && exit 1)
	@test -f $(TEST_DIR)/integration_tests.sh || (echo "$(RED)Missing: integration_tests.sh$(NC)" && exit 1)
	@test -f $(TEST_DIR)/acceptance_tests.sh || (echo "$(RED)Missing: acceptance_tests.sh$(NC)" && exit 1)
	@test -f $(TEST_DIR)/test_runner.sh || (echo "$(RED)Missing: test_runner.sh$(NC)" && exit 1)
	@echo "$(GREEN)Test harness validated successfully$(NC)"

# Default test target
.DEFAULT_GOAL := help
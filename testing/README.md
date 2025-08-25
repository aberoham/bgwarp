# unwarp test harness

Emergency WARP disconnect tool test suite. Validates functionality and security without requiring actual WARP disconnection or root privileges.

## Quick Start

```bash
# Run all tests
make test

# Run specific test suites  
make test-unit        # Basic functionality
make test-security    # Permission and auth validation
make test-integration # Component interaction
make test-quick       # Skip optional tests

# Clean artifacts
make clean
```

## Architecture

```
testing/
├── bin/              # Test binaries
├── output/           # Logs and results
├── mocks/            # Mock commands
├── system_checks.sh  # WARP detection
├── unit_tests.sh     # Functionality tests
├── security_tests.sh # Security validation
├── integration_tests.sh # Integration tests
├── acceptance_tests.sh  # Manual validation
├── test_runner.sh    # Test orchestrator
└── Makefile         # Build automation
```

Test artifacts stay in `testing/`:
- **bin/**: Test binary without setuid
- **output/**: Test logs and temporary files
- **mocks/**: Mock executables for dangerous operations

## Test Suites

### System Checks
Detects WARP installation, service status, and missing dependencies. Exports results for other tests.

### Unit Tests  
Command parsing, argument validation, help output, permission checks.

### Security Tests
Setuid requirements, permission enforcement, binary integrity, authentication flow.

### Integration Tests
Mock command execution, network interface detection, recovery job creation, error handling.

### Acceptance Tests
Interactive Touch ID prompts, user confirmations, visual output verification.

## Local Testing

Prerequisites:
- Xcode Command Line Tools
- Optional: Cloudflare WARP, Touch ID, sudo access

```bash
cd testing

# Check prerequisites
./system_checks.sh

# Run full suite
./test_runner.sh

# Or use make targets
make test
```

Development workflow:
```bash
# Make changes
vim ../unwarp.m

# Verify changes
make test-quick

# Run specific suite
make test-security

# Clean up
make clean
```

## CI Limitations

GitHub Actions macOS runners cannot test:
- Setuid permissions
- Touch ID authentication  
- WARP connection/disconnection
- Network recovery operations
- Real sudo operations

The test suite adapts by using mocks and skipping hardware-dependent tests.

```yaml
# CI workflow example
- name: Run tests
  run: |
    cd testing
    make test-ci  # Non-interactive mode
```

## Writing Tests

Add test functions to the appropriate suite:

```bash
# In unit_tests.sh
test_new_feature() {
    local output
    output=$("$TEST_BINARY" --new-flag 2>&1) || true
    assert_contains "$output" "expected text" "Description"
}

# Register in main function
run_test "new_feature" test_new_feature
```

Available helpers from `test_helpers.sh`:
- `assert_contains` - Check for text in output
- `assert_matches` - Match regex pattern
- `assert_exit_code` - Verify exit code
- `create_mock_command` - Create mock executables
- `skip_test` - Skip with reason

Mock dangerous operations:
```bash
create_mock_command "warp-cli" 'echo "MOCK: warp-cli $*"'
setup_mock_path
# Run tests
restore_path
```

## Troubleshooting

**WARP not found**: Tests using mocks will still run. Install WARP for full coverage.

**Setuid errors**: Expected for test binary. Production binary requires proper installation.

**Touch ID unavailable**: Falls back to password authentication.

Debug individual tests:
```bash
# Verbose output
make test-verbose

# Check logs
cat output/test.log
cat output/<test_name>.out

# Run single suite
./unit_tests.sh
```

## Guidelines

- Tests must not affect system state
- Use mocks for destructive operations
- Maintain bash 3.2 compatibility (macOS default)
- Run `make clean` before full test runs
- Write tests before features (TDD)

## License

Part of the unwarp project. See main LICENSE file.
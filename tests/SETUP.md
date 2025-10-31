# Test Setup and Configuration Guide

This guide provides comprehensive instructions for setting up and configuring the fstore-sql test environment across different platforms and scenarios.

## Prerequisites

### Required Software

1. **Docker** (version 20.0 or higher)
   - Docker Desktop for macOS/Windows
   - Docker Engine for Linux
   - Verify installation: `docker --version`

2. **PostgreSQL Client Tools** (psql)
   - macOS: `brew install postgresql`
   - Ubuntu/Debian: `sudo apt-get install postgresql-client`
   - Windows: Download from PostgreSQL official website
   - Verify installation: `psql --version`

3. **Bash Shell** (version 4.0 or higher)
   - Pre-installed on macOS/Linux
   - Windows: Use Git Bash, WSL, or Cygwin
   - Verify installation: `bash --version`

### Optional Tools

- **bc** (for precise timing calculations): `brew install bc` or `apt-get install bc`
- **timeout/gtimeout** (for test timeouts): Usually pre-installed on Linux, `brew install coreutils` on macOS

## Quick Setup

### 1. Clone and Navigate

```bash
git clone <repository-url>
cd fstore-sql
```

### 2. Verify Docker

```bash
# Check Docker is running
docker info

# If not running, start Docker daemon
sudo systemctl start docker  # Linux
# or start Docker Desktop on macOS/Windows
```

### 3. Run Tests

```bash
# Make test runner executable
chmod +x run-tests.sh

# Run all tests
./run-tests.sh

# Run with verbose output
./run-tests.sh --verbose
```

## Detailed Setup Instructions

### macOS Setup

```bash
# Install prerequisites using Homebrew
brew install docker postgresql bc coreutils

# Start Docker Desktop
open -a Docker

# Verify setup
docker --version
psql --version
bash --version

# Run tests
./run-tests.sh --verbose
```

### Linux (Ubuntu/Debian) Setup

```bash
# Update package list
sudo apt-get update

# Install Docker
sudo apt-get install docker.io docker-compose
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER  # Add user to docker group
newgrp docker  # Apply group changes

# Install PostgreSQL client and utilities
sudo apt-get install postgresql-client bc

# Verify setup
docker --version
psql --version

# Run tests
./run-tests.sh --verbose
```

### Windows Setup

#### Option 1: WSL2 (Recommended)

```bash
# Install WSL2 and Ubuntu
wsl --install -d Ubuntu

# Inside WSL2, follow Linux setup instructions above
```

#### Option 2: Git Bash

```bash
# Install Git for Windows (includes Git Bash)
# Install Docker Desktop for Windows
# Install PostgreSQL for Windows

# Use Git Bash for running tests
./run-tests.sh --verbose
```

## Test Runner Configuration

### Command Line Options

```bash
./run-tests.sh [OPTIONS]

# Test Categories
--category all              # Run all tests (default)
--category unit             # Run only unit tests
--category integration      # Run only integration tests
--category performance      # Run only performance tests
--category event-sourcing   # Run event sourcing tests only
--category event-streaming  # Run event streaming tests only
--category constraints      # Run constraint tests only

# Output Options
--verbose                   # Enable detailed output
--report-format text        # Text output (default)
--report-format json        # JSON output for automation
--save-report              # Save report to timestamped file

# Database Options
--keep-db                  # Keep test database running after tests
--timeout 300              # Test timeout in seconds (default: 300)

# Examples
./run-tests.sh --category unit --verbose
./run-tests.sh --report-format json --save-report
./run-tests.sh --keep-db --timeout 600
```

### Environment Variables

```bash
# Override test timeout
export TEST_TIMEOUT=600
./run-tests.sh

# Custom database port (if 5433 is in use)
export TEST_DB_PORT=5434
./run-tests.sh

# Custom container name
export TEST_CONTAINER_NAME="my-test-db"
./run-tests.sh
```

### Configuration File

Create a `.testrc` file in the project root for persistent configuration:

```bash
# .testrc - Test runner configuration
export TEST_TIMEOUT=600
export TEST_DB_PORT=5433
export VERBOSE=true
export REPORT_FORMAT=json
```

Load configuration before running tests:

```bash
source .testrc
./run-tests.sh
```

## Database Configuration

### Test Database Settings

The test runner automatically configures a PostgreSQL container with:

- **Image**: `supabase/postgres:15.1.0.82`
- **Port**: `5433` (to avoid conflicts with development database)
- **Database**: `postgres`
- **User**: `postgres`
- **Password**: Auto-generated unique password per test run
- **Schema**: Automatically loaded from `schema.sql`

### Custom Database Configuration

#### Using Existing PostgreSQL Instance

```bash
# Set connection parameters
export DB_HOST=your-db-host
export DB_PORT=5432
export DB_USER=your-username
export DB_NAME=your-test-database
export PGPASSWORD=your-password

# Skip Docker container creation
export USE_EXISTING_DB=true

# Run tests
./run-tests.sh
```

#### Custom Docker Configuration

Create a custom `docker-compose.test.yml`:

```yaml
services:
  test-db:
    image: supabase/postgres:15.1.0.82
    ports:
      - "5433:5432"
    environment:
      POSTGRES_PASSWORD: custom_test_password
      POSTGRES_DB: test_database
      POSTGRES_USER: test_user
    volumes:
      - ./schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro
      - ./test-config.sql:/docker-entrypoint-initdb.d/test-config.sql:ro
    command: postgres -c log_statement=all -c shared_preload_libraries=pg_cron
```

Use custom configuration:

```bash
export DOCKER_COMPOSE_FILE=docker-compose.test.yml
./run-tests.sh
```

## Development Environment Integration

### IDE Integration

#### VS Code

Create `.vscode/tasks.json`:

```json
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Run All Tests",
            "type": "shell",
            "command": "./run-tests.sh",
            "group": "test",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "shared"
            }
        },
        {
            "label": "Run Unit Tests",
            "type": "shell",
            "command": "./run-tests.sh --category unit --verbose",
            "group": "test"
        },
        {
            "label": "Debug Tests (Keep DB)",
            "type": "shell",
            "command": "./run-tests.sh --keep-db --verbose",
            "group": "test"
        }
    ]
}
```

#### IntelliJ/DataGrip

Create run configurations for different test categories.

### Makefile Integration

Add to existing `Makefile`:

```makefile
# Test targets
test: ## Run all tests
	./run-tests.sh

test-unit: ## Run unit tests
	./run-tests.sh --category unit

test-integration: ## Run integration tests
	./run-tests.sh --category integration

test-performance: ## Run performance tests
	./run-tests.sh --category performance

test-verbose: ## Run tests with verbose output
	./run-tests.sh --verbose

test-debug: ## Run tests and keep database for debugging
	./run-tests.sh --keep-db --verbose

test-clean: ## Clean up any leftover test containers
	docker stop fstore-sql-test-db 2>/dev/null || true
	docker rm fstore-sql-test-db 2>/dev/null || true
```

### Git Hooks

#### Pre-commit Hook

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Run critical tests before commit

echo "Running pre-commit tests..."

# Run unit tests only (faster)
if ! ./run-tests.sh --category unit; then
    echo "❌ Unit tests failed. Commit aborted."
    exit 1
fi

echo "✅ Pre-commit tests passed."
exit 0
```

Make executable:

```bash
chmod +x .git/hooks/pre-commit
```

#### Pre-push Hook

Create `.git/hooks/pre-push`:

```bash
#!/bin/bash
# Run full test suite before push

echo "Running pre-push tests..."

if ! ./run-tests.sh; then
    echo "❌ Test suite failed. Push aborted."
    exit 1
fi

echo "✅ All tests passed."
exit 0
```

## CI/CD Integration

### GitHub Actions

Create `.github/workflows/test.yml`:

```yaml
name: Test Suite

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Docker
      uses: docker/setup-buildx-action@v2
    
    - name: Make test runner executable
      run: chmod +x run-tests.sh
    
    - name: Run unit tests
      run: ./run-tests.sh --category unit --report-format json
    
    - name: Run integration tests
      run: ./run-tests.sh --category integration --report-format json
    
    - name: Run performance tests
      run: ./run-tests.sh --category performance --report-format json
    
    - name: Upload test results
      uses: actions/upload-artifact@v3
      if: always()
      with:
        name: test-results
        path: test_report_*.json
```

### GitLab CI

Create `.gitlab-ci.yml`:

```yaml
stages:
  - test

variables:
  DOCKER_DRIVER: overlay2

services:
  - docker:dind

test:
  stage: test
  image: docker:latest
  before_script:
    - apk add --no-cache bash postgresql-client
    - chmod +x run-tests.sh
  script:
    - ./run-tests.sh --report-format json
  artifacts:
    reports:
      junit: test_report_*.json
    when: always
    expire_in: 1 week
```

### Jenkins Pipeline

Create `Jenkinsfile`:

```groovy
pipeline {
    agent any
    
    stages {
        stage('Setup') {
            steps {
                sh 'chmod +x run-tests.sh'
            }
        }
        
        stage('Unit Tests') {
            steps {
                sh './run-tests.sh --category unit --report-format json'
            }
        }
        
        stage('Integration Tests') {
            steps {
                sh './run-tests.sh --category integration --report-format json'
            }
        }
        
        stage('Performance Tests') {
            steps {
                sh './run-tests.sh --category performance --report-format json'
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: 'test_report_*.json', fingerprint: true
        }
    }
}
```

## Troubleshooting

### Common Issues

#### Docker Issues

**Problem**: `Cannot connect to the Docker daemon`
```bash
# Solution: Start Docker daemon
sudo systemctl start docker  # Linux
# or start Docker Desktop on macOS/Windows

# Verify Docker is running
docker info
```

**Problem**: `Port 5433 already in use`
```bash
# Solution: Use different port
export TEST_DB_PORT=5434
./run-tests.sh

# Or find and stop conflicting container
docker ps | grep 5433
docker stop <container_name>
```

**Problem**: `Permission denied` when running Docker commands
```bash
# Solution: Add user to docker group (Linux)
sudo usermod -aG docker $USER
newgrp docker

# Or run with sudo (not recommended for regular use)
sudo ./run-tests.sh
```

#### Database Connection Issues

**Problem**: `Connection refused` or `Database not ready`
```bash
# Solution: Increase startup timeout
./run-tests.sh --timeout 600

# Or check container logs
docker logs fstore-sql-test-db
```

**Problem**: `Authentication failed`
```bash
# Solution: Clear any existing PGPASSWORD
unset PGPASSWORD
./run-tests.sh

# Or check if container is using correct password
docker exec fstore-sql-test-db env | grep POSTGRES_PASSWORD
```

**Problem**: `Schema not loaded`
```bash
# Solution: Verify schema.sql exists and is readable
ls -la schema.sql
cat schema.sql | head -20

# Check container logs for initialization errors
docker logs fstore-sql-test-db | grep -i error
```

#### Test Execution Issues

**Problem**: Tests timeout frequently
```bash
# Solution: Increase test timeout
export TEST_TIMEOUT=600
./run-tests.sh

# Or run specific failing test with debug
./run-tests.sh --keep-db --verbose tests/unit/specific-test.sql
```

**Problem**: `Test framework not found`
```bash
# Solution: Verify test utilities exist
ls -la tests/utils/
cat tests/utils/test-helpers.sql | head -10

# Run from correct directory
pwd  # Should be in fstore-sql root directory
```

**Problem**: Random test failures
```bash
# Solution: Check for test data conflicts
# Ensure tests clean up properly
grep -r "DELETE FROM" tests/

# Run tests individually to isolate issues
./run-tests.sh tests/unit/event-sourcing/test_append_event.sql
```

#### Performance Issues

**Problem**: Tests run very slowly
```bash
# Solution: Check system resources
docker stats fstore-sql-test-db

# Reduce test scope for development
./run-tests.sh --category unit

# Use faster storage for Docker
# (configure Docker to use SSD storage)
```

**Problem**: Out of memory errors
```bash
# Solution: Increase Docker memory limits
# Docker Desktop: Settings > Resources > Memory

# Or reduce concurrent test execution
export MAX_PARALLEL_TESTS=1
./run-tests.sh
```

### Debug Mode

Enable comprehensive debugging:

```bash
# Enable all debug output
export DEBUG=true
export VERBOSE=true
./run-tests.sh --keep-db --verbose

# Connect to test database for manual inspection
psql -h localhost -p 5433 -U postgres -d postgres

# Check test results table
SELECT * FROM test_results ORDER BY created_at DESC LIMIT 10;

# Check test metrics
SELECT * FROM test_metrics ORDER BY metric_id DESC LIMIT 10;
```

### Log Analysis

```bash
# View container logs
docker logs fstore-sql-test-db

# Follow logs in real-time
docker logs -f fstore-sql-test-db

# Filter for errors
docker logs fstore-sql-test-db 2>&1 | grep -i error

# Save logs for analysis
docker logs fstore-sql-test-db > test-db-logs.txt 2>&1
```

## Known Issues and Limitations

### Current Test Framework Issues

**Issue**: Some unit tests may fail when run together due to data isolation issues
- **Symptoms**: Duplicate key violations, foreign key constraint errors
- **Workaround**: Run individual test files or categories separately
- **Example**: `./run-tests.sh tests/unit/event-sourcing/test_append_event.sql`
- **Status**: Under investigation - the core fstore-sql functionality works correctly

**Issue**: Complex test scenarios may have timing dependencies
- **Symptoms**: Intermittent test failures, timeout errors
- **Workaround**: Use `--timeout` flag to increase test timeout
- **Example**: `./run-tests.sh --timeout 600`
- **Status**: Tests are being simplified to reduce complexity

**Issue**: Test framework functions may conflict in some environments
- **Symptoms**: "Function not found" errors, ambiguous column references
- **Workaround**: Ensure clean database state, run tests individually
- **Status**: Framework is being simplified for better reliability

### Recommended Testing Approach

For the most reliable testing experience:

1. **Test individual components**:
   ```bash
   ./run-tests.sh tests/unit/event-sourcing/test_append_event.sql
   ./run-tests.sh tests/unit/event-streaming/test_register_view.sql
   ```

2. **Test by category**:
   ```bash
   ./run-tests.sh --category unit
   ./run-tests.sh --category integration
   ```

3. **Use verbose mode for debugging**:
   ```bash
   ./run-tests.sh --verbose --keep-db
   ```

4. **Manual testing for complex scenarios**:
   ```bash
   # Start test database
   docker run -d --name manual-test -p 5434:5432 \
     -e POSTGRES_PASSWORD=test123 \
     -v $(pwd)/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro \
     supabase/postgres:15.1.0.82
   
   # Run manual tests
   PGPASSWORD=test123 psql -h localhost -p 5434 -U postgres -d postgres
   ```

## Performance Tuning

### Database Performance

```sql
-- Add to custom test configuration
-- test-config.sql

-- Optimize for testing (not production)
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
ALTER SYSTEM SET wal_buffers = '16MB';
ALTER SYSTEM SET default_statistics_target = 100;

-- Reduce durability for faster tests (test data is disposable)
ALTER SYSTEM SET synchronous_commit = off;
ALTER SYSTEM SET fsync = off;
ALTER SYSTEM SET full_page_writes = off;

SELECT pg_reload_conf();
```

### Test Execution Performance

```bash
# Run tests in parallel (experimental)
export PARALLEL_TESTS=true
./run-tests.sh

# Skip performance tests during development
./run-tests.sh --category unit,integration

# Use faster assertion methods
# (prefer simple assertions over complex ones)
```

## Security Considerations

### Test Data Security

- Test databases use auto-generated passwords
- Test data is automatically cleaned up
- No production data should be used in tests
- Test containers are isolated from production networks

### Network Security

```bash
# Run tests in isolated Docker network
docker network create test-network
export DOCKER_NETWORK=test-network
./run-tests.sh
```

### Access Control

```bash
# Restrict test database access
export DB_ALLOWED_HOSTS="localhost,127.0.0.1"
./run-tests.sh
```

## Monitoring and Metrics

### Test Metrics Collection

```sql
-- Query test performance metrics
SELECT 
    test_category,
    COUNT(*) as total_tests,
    AVG(execution_time_ms) as avg_time,
    MAX(execution_time_ms) as max_time,
    MIN(execution_time_ms) as min_time
FROM test_results 
WHERE created_at > NOW() - INTERVAL '1 day'
GROUP BY test_category;
```

### Continuous Monitoring

```bash
# Set up test result monitoring
./run-tests.sh --report-format json > latest-results.json

# Parse results for monitoring systems
jq '.summary.success_rate' latest-results.json
jq '.summary.total_execution_time' latest-results.json
```

This comprehensive setup guide should help you configure and run the fstore-sql test suite in any environment. For additional help, refer to the main [README.md](README.md) or create an issue in the project repository.
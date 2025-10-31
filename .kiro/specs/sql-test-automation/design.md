# Design Document

## Overview

The SQL test automation system will provide comprehensive testing for the fstore-sql event store using a combination of SQL test scripts, shell automation, and Docker containerization. The design follows a modular approach with separate test categories, automated setup/teardown, and detailed reporting capabilities.

## Architecture

### Test Framework Structure

```
tests/
├── setup/
│   ├── test-database.sql      # Test database initialization
│   └── test-data.sql          # Common test data setup
├── unit/
│   ├── event-sourcing/        # Event sourcing API tests
│   ├── event-streaming/       # Event streaming API tests
│   └── constraints/           # Database constraint tests
├── integration/
│   ├── concurrent-access/     # Multi-consumer scenarios
│   └── end-to-end/           # Complete workflow tests
├── performance/
│   ├── load-tests/           # High-volume scenarios
│   └── benchmarks/           # Performance measurements
├── utils/
│   ├── test-helpers.sql      # Reusable test functions
│   └── assertions.sql        # Custom assertion functions
└── run-tests.sh              # Main test runner script
```

### Test Execution Flow

1. **Environment Setup**: Initialize clean test database with schema
2. **Test Discovery**: Scan test directories for SQL test files
3. **Test Execution**: Run tests in categories with proper isolation
4. **Result Collection**: Capture test outcomes and performance metrics
5. **Cleanup**: Reset database state between test runs
6. **Reporting**: Generate comprehensive test reports

## Components and Interfaces

### Test Runner (run-tests.sh)

**Purpose**: Main orchestration script for test execution
**Responsibilities**:
- Database container management
- Test environment setup and teardown
- Test file discovery and execution
- Result aggregation and reporting
- Error handling and cleanup

**Interface**:
```bash
./run-tests.sh [options]
  --category <unit|integration|performance|all>
  --verbose                    # Detailed output
  --keep-db                   # Don't cleanup database after tests
  --report-format <text|json> # Output format
```

### SQL Test Framework

**Purpose**: Standardized SQL testing utilities
**Components**:
- `test_assert()`: Generic assertion function
- `test_expect_error()`: Validate expected failures
- `test_setup()`: Per-test initialization
- `test_cleanup()`: Per-test cleanup
- `test_report()`: Result reporting

**Example Test Structure**:
```sql
-- Test: Basic event appending
SELECT test_setup('test_append_event');

-- Setup test data
SELECT register_decider_event('test_decider', 'test_event', 'Test event', 1);

-- Execute test
SELECT test_assert(
    (SELECT count(*) FROM append_event('test_event', gen_random_uuid(), 'test_decider', 'test-id-1', '{}', gen_random_uuid(), null, 1)) = 1,
    'Should successfully append first event'
);

SELECT test_cleanup('test_append_event');
```

### Database Test Environment

**Purpose**: Isolated PostgreSQL instance for testing
**Configuration**:
- Uses same Supabase PostgreSQL image as development
- Automatically imports schema.sql and extensions.sql
- Separate database for each test run
- Configurable connection parameters

### Test Categories

#### Unit Tests
- **Event Sourcing API**: Test each function individually
- **Event Streaming API**: Test streaming functions in isolation
- **Database Constraints**: Validate all triggers and rules

#### Integration Tests
- **Concurrent Access**: Multi-consumer scenarios
- **End-to-End Workflows**: Complete event sourcing and streaming flows
- **Cross-Function Dependencies**: Test function interactions

#### Performance Tests
- **Load Testing**: High-volume event processing
- **Concurrency Testing**: Multiple simultaneous consumers
- **Benchmark Testing**: Performance baseline measurements

## Data Models

### Test Result Schema

```sql
CREATE TABLE test_results (
    test_id SERIAL PRIMARY KEY,
    test_name TEXT NOT NULL,
    test_category TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('PASS', 'FAIL', 'SKIP')),
    execution_time_ms BIGINT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE test_metrics (
    metric_id SERIAL PRIMARY KEY,
    test_id INTEGER REFERENCES test_results(test_id),
    metric_name TEXT NOT NULL,
    metric_value NUMERIC,
    metric_unit TEXT
);
```

### Test Data Patterns

**Standard Test Deciders**:
- `test_decider_1`: Basic event sourcing tests
- `test_decider_2`: Constraint validation tests
- `test_decider_concurrent`: Concurrency tests

**Standard Test Views**:
- `test_view_basic`: Simple streaming tests
- `test_view_concurrent`: Multi-consumer tests
- `test_view_performance`: Load testing

## Error Handling

### Test Failure Management
- **Expected Failures**: Use `test_expect_error()` for constraint validation
- **Unexpected Failures**: Capture full error context and stack traces
- **Timeout Handling**: Set reasonable timeouts for long-running tests
- **Resource Cleanup**: Ensure database state is reset even on failures

### Error Reporting
- **Detailed Messages**: Include expected vs actual results
- **Context Information**: Show relevant database state
- **Stack Traces**: Capture PostgreSQL error details
- **Suggestions**: Provide hints for common failure patterns

## Testing Strategy

### Test Coverage Areas

1. **API Function Testing**
   - All documented function parameters
   - Return value validation
   - Error condition handling
   - Edge cases and boundary conditions

2. **Constraint Validation**
   - Foreign key constraints
   - Unique constraints
   - Custom triggers and rules
   - Immutability enforcement

3. **Concurrency Testing**
   - Optimistic locking behavior
   - Lock timeout scenarios
   - Concurrent consumer coordination
   - Race condition prevention

4. **Data Integrity**
   - Event ordering within partitions
   - Cross-partition independence
   - Transaction isolation
   - Rollback behavior

### Test Data Management

**Isolation Strategy**:
- Each test uses unique identifiers
- Database reset between test categories
- Parallel test execution where safe
- Cleanup verification after each test

**Data Generation**:
- Deterministic test data for repeatability
- Random data for stress testing
- Edge case data for boundary testing
- Large datasets for performance testing

## Performance Considerations

### Test Execution Optimization
- **Parallel Execution**: Run independent tests concurrently
- **Database Pooling**: Reuse connections where possible
- **Selective Testing**: Support running specific test subsets
- **Caching**: Cache test database setup when possible

### Performance Monitoring
- **Execution Time Tracking**: Monitor test duration trends
- **Resource Usage**: Track memory and CPU consumption
- **Database Metrics**: Monitor connection counts and query performance
- **Bottleneck Identification**: Identify slow tests and optimization opportunities

## Integration Points

### Docker Integration
- **Container Management**: Automated PostgreSQL container lifecycle
- **Volume Mounting**: Share test files with container
- **Network Configuration**: Isolated test network
- **Health Checks**: Verify database readiness before testing

### CI/CD Integration
- **Exit Codes**: Proper success/failure signaling
- **Report Formats**: JSON output for automated processing
- **Artifact Generation**: Test reports and logs
- **Environment Variables**: Configurable test parameters

### Development Workflow
- **Pre-commit Hooks**: Run critical tests before commits
- **Watch Mode**: Continuous testing during development
- **IDE Integration**: Support for running individual tests
- **Debug Mode**: Enhanced logging for troubleshooting
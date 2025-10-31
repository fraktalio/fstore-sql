# fstore-sql Test Suite

Comprehensive automated testing framework for the fstore-sql event store, providing validation for all event sourcing and event streaming functionality.

## Overview

This test suite provides comprehensive coverage of the fstore-sql event store using a combination of SQL test scripts, shell automation, and Docker containerization. The framework follows a modular approach with separate test categories, automated setup/teardown, and detailed reporting capabilities.

## Quick Start

```bash
# Run all tests
./run-tests.sh

# Run specific test category
./run-tests.sh --category unit

# Run with verbose output
./run-tests.sh --verbose

# Keep database running for debugging
./run-tests.sh --keep-db
```

## Test Structure

```
tests/
├── README.md                 # This documentation
├── setup/                    # Database initialization scripts
│   ├── test-database.sql     # Test database setup
│   └── test-data.sql         # Common test data patterns
├── unit/                     # Unit tests for individual functions
│   ├── event-sourcing/       # Event sourcing API tests
│   ├── event-streaming/      # Event streaming API tests
│   └── constraints/          # Database constraint tests
├── integration/              # Integration and workflow tests
│   ├── concurrent-access/    # Multi-consumer scenarios
│   └── end-to-end/          # Complete workflow tests
├── performance/              # Performance and load tests
│   ├── load-tests/          # High-volume scenarios
│   └── benchmarks/          # Performance measurements
└── utils/                    # Test framework utilities
    ├── test-helpers.sql      # Core testing functions
    └── assertions.sql        # Specialized assertion functions
```

## Test Framework Functions

### Core Test Functions

#### `test_setup(test_name, test_category)`
Initialize a test with proper state tracking and timing.

```sql
SELECT test_setup('my_test_name', 'unit');
```

#### `test_cleanup(test_name, status, error_msg)`
Clean up after a test and record results. Usually called automatically by assertion failures.

```sql
SELECT test_cleanup('my_test_name', 'PASS');
```

#### `test_assert(condition, message)`
Generic assertion function that fails the test if condition is false.

```sql
SELECT test_assert(
    (SELECT count(*) FROM events WHERE decider_id = 'test-id') = 1,
    'Should have exactly one event'
);
```

#### `test_assert_equals(expected, actual, message)`
Assert that two values are equal with detailed error reporting.

```sql
SELECT test_assert_equals(
    'expected_value'::TEXT,
    actual_value,
    'Values should match'
);
```

#### `test_assert_not_null(value, message)`
Assert that a value is not null.

```sql
SELECT test_assert_not_null(
    result_record.event_id,
    'Event ID should not be null'
);
```

#### `test_assert_null(value, message)`
Assert that a value is null.

```sql
SELECT test_assert_null(
    result_record.previous_id,
    'First event should have null previous_id'
);
```

#### `test_expect_error(sql_statement, expected_error_pattern, message)`
Verify that a SQL statement raises an expected error.

```sql
SELECT test_expect_error(
    'SELECT append_event(''invalid'', gen_random_uuid(), ''nonexistent'', ''test'', ''{}'', gen_random_uuid(), null, 1)',
    'violates foreign key constraint',
    'Should reject invalid decider/event combination'
);
```

### Event Store Specialized Assertions

#### `test_assert_event_exists(event_id, decider_id, decider, message)`
Verify that a specific event exists in the event store.

```sql
SELECT test_assert_event_exists(
    event_id,
    'test-decider-1',
    'test_decider',
    'Event should exist after appending'
);
```

#### `test_assert_event_count(decider_id, decider, expected_count, message)`
Verify the number of events for a specific decider.

```sql
SELECT test_assert_event_count(
    'test-decider-1',
    'test_decider',
    2,
    'Should have 2 events after appending both'
);
```

#### `test_assert_event_ordering(decider_id, decider, message)`
Verify that events are properly ordered within a decider stream.

```sql
SELECT test_assert_event_ordering(
    'test-decider-1',
    'test_decider',
    'Events should be properly ordered'
);
```

#### `test_assert_decider_event_registered(decider, event, event_version, message)`
Verify that a decider-event combination is properly registered.

```sql
SELECT test_assert_decider_event_registered(
    'test_decider',
    'test_event',
    1,
    'Decider event should be registered'
);
```

#### `test_assert_view_registered(view, message)`
Verify that a view is registered for event streaming.

```sql
SELECT test_assert_view_registered(
    'test_view',
    'View should be registered'
);
```

#### `test_assert_lock_exists(view, decider_id, message)`
Verify that a lock exists for a view and decider combination.

```sql
SELECT test_assert_lock_exists(
    'test_view',
    'test-decider-1',
    'Lock should exist for streaming'
);
```

#### `test_assert_stream_final(decider_id, decider, message)`
Verify that an event stream is marked as final.

```sql
SELECT test_assert_stream_final(
    'test-decider-1',
    'test_decider',
    'Stream should be final after final event'
);
```

### Performance and Metrics

#### `test_record_metric(metric_name, metric_value, metric_unit)`
Record a performance metric for the current test.

```sql
SELECT test_record_metric('execution_time', 150.5, 'ms');
SELECT test_record_metric('events_processed', 1000, 'count');
```

#### `test_get_results_summary()`
Get a summary of test results by category.

```sql
SELECT * FROM test_get_results_summary();
```

## Writing New Tests

### Basic Test Structure

Every test file should follow this structure:

```sql
-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM events WHERE decider_id LIKE 'test_%';
DELETE FROM deciders WHERE decider LIKE 'test_%';
SELECT test_clear_results();

-- Test: Description of what you're testing
SELECT test_setup('test_name_here');

DO $test$
DECLARE
    -- Declare variables here
    event_id UUID := gen_random_uuid();
    result_record events;
BEGIN
    -- Setup test data
    PERFORM register_decider_event('test_decider', 'test_event', 'Description', 1);
    
    -- Execute the functionality being tested
    SELECT * INTO result_record FROM append_event(
        'test_event', 
        event_id, 
        'test_decider', 
        'test-decider-1', 
        '{"test": "data"}'::jsonb, 
        gen_random_uuid(), 
        null, 
        1
    );
    
    -- Verify results with assertions
    PERFORM test_assert_not_null(result_record.event_id, 'Should return event_id');
    PERFORM test_assert_equals(event_id, result_record.event_id, 'Should return correct event_id');
    
    -- Test completed successfully
    PERFORM test_cleanup('test_name_here', 'PASS');
END;
$test$;
```

### Test Data Conventions

- Use `test_` prefix for all test data (decider_ids, view names, etc.)
- Use deterministic UUIDs when possible for repeatability
- Clean up test data at the beginning of each test file
- Use meaningful names that describe the test scenario

### Error Testing Pattern

```sql
-- Test: Should reject invalid input
SELECT test_setup('test_invalid_input');

SELECT test_expect_error(
    'SELECT append_event(''nonexistent_event'', gen_random_uuid(), ''test_decider'', ''test-id'', ''{}'', gen_random_uuid(), null, 1)',
    'violates foreign key constraint',
    'Should reject unregistered event type'
);

SELECT test_cleanup('test_invalid_input', 'PASS');
```

### Performance Testing Pattern

```sql
-- Test: Performance benchmark
SELECT test_setup('test_performance_benchmark');

DO $test$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    execution_time NUMERIC;
    i INTEGER;
BEGIN
    -- Setup
    PERFORM register_decider_event('test_decider', 'test_event', 'Description', 1);
    
    -- Measure performance
    start_time := clock_timestamp();
    
    -- Execute operations
    FOR i IN 1..1000 LOOP
        PERFORM append_event(
            'test_event', 
            gen_random_uuid(), 
            'test_decider', 
            'test-decider-' || i, 
            '{"iteration": ' || i || '}'::jsonb, 
            gen_random_uuid(), 
            null, 
            1
        );
    END LOOP;
    
    end_time := clock_timestamp();
    execution_time := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    
    -- Record metrics
    PERFORM test_record_metric('bulk_insert_time', execution_time, 'ms');
    PERFORM test_record_metric('events_per_second', 1000.0 / (execution_time / 1000.0), 'ops/sec');
    
    -- Verify results
    PERFORM test_assert_event_count('test-decider-1', 'test_decider', 1, 'Should have created events');
    
    PERFORM test_cleanup('test_performance_benchmark', 'PASS');
END;
$test$;
```

## Test Categories

### Unit Tests (`tests/unit/`)

Test individual functions in isolation:

- **event-sourcing/**: Tests for `register_decider_event`, `append_event`, `get_events`, `get_last_event`
- **event-streaming/**: Tests for `register_view`, `stream_events`, `ack_event`, `nack_event`, `schedule_nack_event`
- **constraints/**: Tests for database triggers, constraints, and data integrity rules

### Integration Tests (`tests/integration/`)

Test interactions between components:

- **concurrent-access/**: Multi-consumer scenarios, lock contention, concurrent producers
- **end-to-end/**: Complete workflows combining event sourcing and streaming

### Performance Tests (`tests/performance/`)

Test system performance and scalability:

- **load-tests/**: High-volume event processing, concurrent consumer performance
- **benchmarks/**: Performance baseline measurements, stress testing

## Test Runner Usage

### Basic Usage

```bash
# Run all tests
./run-tests.sh

# Run specific category
./run-tests.sh --category unit
./run-tests.sh --category integration
./run-tests.sh --category performance

# Run specific subcategory
./run-tests.sh --category event-sourcing
./run-tests.sh --category event-streaming
./run-tests.sh --category constraints
```

### Advanced Options

```bash
# Verbose output with detailed test information
./run-tests.sh --verbose

# Keep database running after tests (useful for debugging)
./run-tests.sh --keep-db

# JSON output format
./run-tests.sh --report-format json

# Custom timeout for individual tests
./run-tests.sh --timeout 600

# Run specific test file
./run-tests.sh tests/unit/event-sourcing/test_append_event.sql
```

### Environment Variables

```bash
# Override test timeout
export TEST_TIMEOUT=600
./run-tests.sh

# Custom database port (if needed)
export TEST_DB_PORT=5434
./run-tests.sh
```

## Debugging Tests

### Keeping Database Running

Use `--keep-db` flag to keep the test database running after tests complete:

```bash
./run-tests.sh --keep-db --category unit

# Connect to the test database
psql -h localhost -p 5433 -U postgres -d postgres
```

### Verbose Output

Use `--verbose` flag to see detailed test output:

```bash
./run-tests.sh --verbose --category event-sourcing
```

### Manual Test Execution

You can run individual test files manually:

```bash
# Start test database
docker run -d --name fstore-test-db -p 5433:5432 \
  -e POSTGRES_PASSWORD=test123 \
  -v $(pwd)/schema.sql:/docker-entrypoint-initdb.d/schema.sql:ro \
  supabase/postgres:15.1.0.82

# Wait for database to be ready
sleep 10

# Run specific test
PGPASSWORD=test123 psql -h localhost -p 5433 -U postgres -d postgres \
  -f tests/unit/event-sourcing/test_append_event.sql

# Cleanup
docker stop fstore-test-db && docker rm fstore-test-db
```

## Common Issues and Solutions

### Docker Issues

**Problem**: Docker daemon not running
```bash
# Solution: Start Docker daemon
sudo systemctl start docker  # Linux
# or start Docker Desktop on macOS/Windows
```

**Problem**: Port conflicts
```bash
# Solution: Use different port
export TEST_DB_PORT=5434
./run-tests.sh
```

### Database Connection Issues

**Problem**: Connection refused
```bash
# Solution: Wait longer for database startup
./run-tests.sh --timeout 600
```

**Problem**: Authentication failed
```bash
# Solution: Check if PGPASSWORD is set correctly
unset PGPASSWORD
./run-tests.sh
```

### Test Failures

**Problem**: Tests fail due to existing data
```bash
# Solution: Tests should clean up their own data
# Add this to the beginning of your test file:
DELETE FROM events WHERE decider_id LIKE 'test_%';
DELETE FROM deciders WHERE decider LIKE 'test_%';
```

**Problem**: Timing-sensitive tests fail intermittently
```bash
# Solution: Add appropriate delays or use more robust assertions
# Instead of exact timing, test for ranges or use retry logic
```

## Contributing New Tests

1. **Choose the appropriate category** (unit/integration/performance)
2. **Follow naming conventions** (`test_*.sql`)
3. **Use the test framework functions** for consistency
4. **Include proper cleanup** at the beginning of test files
5. **Add meaningful assertions** with descriptive messages
6. **Test both positive and negative cases**
7. **Document complex test scenarios** with comments

### Test File Template

```sql
-- ##########################################################################################
-- ##########################################################################################
-- ######                        [FEATURE NAME] TESTS                             ######
-- ##########################################################################################
-- ##########################################################################################

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM events WHERE decider_id LIKE 'test_%';
DELETE FROM deciders WHERE decider LIKE 'test_%';
DELETE FROM views WHERE view LIKE 'test_%';
DELETE FROM locks WHERE view LIKE 'test_%';
SELECT test_clear_results();

-- ##########################################################################################
-- ######                           POSITIVE TEST CASES                            ######
-- ##########################################################################################

-- Test: [Description of positive test case]
SELECT test_setup('test_positive_case');
-- Test implementation here
SELECT test_cleanup('test_positive_case', 'PASS');

-- ##########################################################################################
-- ######                           NEGATIVE TEST CASES                            ######
-- ##########################################################################################

-- Test: [Description of negative test case]
SELECT test_setup('test_negative_case');
-- Test implementation here
SELECT test_cleanup('test_negative_case', 'PASS');

-- ##########################################################################################
-- ######                            EDGE CASES                                    ######
-- ##########################################################################################

-- Test: [Description of edge case]
SELECT test_setup('test_edge_case');
-- Test implementation here
SELECT test_cleanup('test_edge_case', 'PASS');
```

## Performance Benchmarks

The test suite includes performance benchmarks that establish baseline performance metrics:

- **Event Appending**: Measures throughput for single and bulk event insertion
- **Event Retrieval**: Measures query performance for event retrieval operations
- **Concurrent Streaming**: Measures performance under concurrent consumer load
- **Lock Management**: Measures overhead of lock acquisition and release

Results are automatically collected and can be used for performance regression detection.
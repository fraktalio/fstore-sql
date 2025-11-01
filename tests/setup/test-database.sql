-- ##########################################################################################
-- ##########################################################################################
-- ######                          TEST DATABASE INITIALIZATION                    ######
-- ##########################################################################################
-- ##########################################################################################

-- This script initializes a clean test database with the event store schema
-- and test framework utilities

\echo 'Initializing test database...'

-- Drop existing test tables if they exist (for clean slate)
DROP TABLE IF EXISTS test_metrics CASCADE;
DROP TABLE IF EXISTS test_results CASCADE;
DROP TABLE IF EXISTS test_state CASCADE;

-- Drop existing event store tables if they exist (for clean slate)
DROP TABLE IF EXISTS locks CASCADE;
DROP TABLE IF EXISTS views CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS deciders CASCADE;

-- Import the main event store schema
\echo 'Loading event store schema...'
\i schema.sql

-- Import test framework utilities
\echo 'Loading test framework utilities...'
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Create test-specific indexes for better performance
CREATE INDEX IF NOT EXISTS test_results_name_idx ON test_results(test_name);
CREATE INDEX IF NOT EXISTS test_results_category_idx ON test_results(test_category);
CREATE INDEX IF NOT EXISTS test_results_status_idx ON test_results(status);
CREATE INDEX IF NOT EXISTS test_results_created_at_idx ON test_results(created_at);

-- Create test-specific views for easier querying
CREATE OR REPLACE VIEW test_summary AS
SELECT 
    test_category,
    COUNT(*) as total_tests,
    COUNT(*) FILTER (WHERE status = 'PASS') as passed,
    COUNT(*) FILTER (WHERE status = 'FAIL') as failed,
    COUNT(*) FILTER (WHERE status = 'SKIP') as skipped,
    ROUND(AVG(execution_time_ms), 2) as avg_execution_time_ms,
    ROUND(MIN(execution_time_ms), 2) as min_execution_time_ms,
    ROUND(MAX(execution_time_ms), 2) as max_execution_time_ms
FROM test_results
GROUP BY test_category
ORDER BY test_category;

CREATE OR REPLACE VIEW failed_tests AS
SELECT 
    test_name,
    test_category,
    error_message,
    execution_time_ms,
    created_at
FROM test_results
WHERE status = 'FAIL'
ORDER BY created_at DESC;

-- Set up test database configuration
-- Increase work memory for better performance during tests
SET work_mem = '64MB';

-- Set timezone for consistent test results
SET timezone = 'UTC';

\echo 'Test database initialization complete!'
\echo 'Available test utilities:'
\echo '  - test_setup(test_name, test_category)'
\echo '  - test_cleanup(test_name, status, error_msg)'
\echo '  - test_assert(condition, message)'
\echo '  - test_assert_equals(expected, actual, message)'
\echo '  - test_expect_error(sql_statement, error_pattern, message)'
\echo '  - test_clear_results()'
\echo '  - test_get_results_summary()'
\echo ''
\echo 'Available test views:'
\echo '  - test_summary: Aggregated test results by category'
\echo '  - failed_tests: Details of failed tests'
\echo ''
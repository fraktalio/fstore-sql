-- ##########################################################################################
-- ##########################################################################################
-- ######                            SQL TEST FRAMEWORK                            ######
-- ##########################################################################################
-- ##########################################################################################

-- Test result tracking table
CREATE TABLE IF NOT EXISTS test_results (
    test_id SERIAL PRIMARY KEY,
    test_name TEXT NOT NULL,
    test_category TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('PASS', 'FAIL', 'SKIP')),
    execution_time_ms BIGINT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Test metrics table for performance tracking
CREATE TABLE IF NOT EXISTS test_metrics (
    metric_id SERIAL PRIMARY KEY,
    test_id INTEGER REFERENCES test_results(test_id),
    metric_name TEXT NOT NULL,
    metric_value NUMERIC,
    metric_unit TEXT
);

-- Global test state tracking
CREATE TABLE IF NOT EXISTS test_state (
    key TEXT PRIMARY KEY,
    value TEXT
);

-- Initialize test state (only if not already initialized)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM test_state WHERE key = 'current_test') THEN
        INSERT INTO test_state (key, value) VALUES ('current_test', '');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM test_state WHERE key = 'test_start_time') THEN
        INSERT INTO test_state (key, value) VALUES ('test_start_time', '');
    END IF;
END $$;

-- ##########################################################################################
-- ######                              CORE TEST FUNCTIONS                         ######
-- ##########################################################################################

-- API: Setup a test - initialize test state and record start time
CREATE OR REPLACE FUNCTION test_setup(test_name TEXT, test_category TEXT DEFAULT 'unit')
    RETURNS VOID AS
$$
BEGIN
    -- Update current test state
    UPDATE test_state SET value = test_name WHERE key = 'current_test';
    UPDATE test_state SET value = EXTRACT(EPOCH FROM NOW())::TEXT WHERE key = 'test_start_time';
    
    -- Log test start
    RAISE NOTICE 'Starting test: %', test_name;
END;
$$ LANGUAGE plpgsql;

-- API: Cleanup after a test - record results and reset state
CREATE OR REPLACE FUNCTION test_cleanup(test_name TEXT, status TEXT DEFAULT 'PASS', error_msg TEXT DEFAULT NULL)
    RETURNS VOID AS
$$
DECLARE
    start_time NUMERIC;
    execution_time BIGINT;
    current_category TEXT;
BEGIN
    -- Calculate execution time
    SELECT value::NUMERIC INTO start_time FROM test_state WHERE key = 'test_start_time';
    execution_time := (EXTRACT(EPOCH FROM NOW()) - start_time) * 1000;
    
    -- Determine category from test name or use default
    current_category := CASE 
        WHEN test_name LIKE '%unit%' THEN 'unit'
        WHEN test_name LIKE '%integration%' THEN 'integration'
        WHEN test_name LIKE '%performance%' THEN 'performance'
        ELSE 'unit'
    END;
    
    -- Record test result
    INSERT INTO test_results (test_name, test_category, status, execution_time_ms, error_message)
    VALUES (test_name, current_category, status, execution_time, error_msg);
    
    -- Reset test state
    UPDATE test_state SET value = '' WHERE key = 'current_test';
    UPDATE test_state SET value = '' WHERE key = 'test_start_time';
    
    -- Log test completion
    RAISE NOTICE 'Test completed: % - % (% ms)', test_name, status, execution_time;
END;
$$ LANGUAGE plpgsql;

-- API: Generic assertion function
CREATE OR REPLACE FUNCTION test_assert(condition BOOLEAN, message TEXT)
    RETURNS BOOLEAN AS
$$
DECLARE
    current_test TEXT;
BEGIN
    SELECT test_state.value INTO current_test FROM test_state WHERE key = 'current_test';
    
    IF NOT condition THEN
        PERFORM test_cleanup(current_test, 'FAIL', message);
        RAISE EXCEPTION 'Assertion failed: %', message;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- API: Assert that two values are equal
CREATE OR REPLACE FUNCTION test_assert_equals(expected ANYELEMENT, actual ANYELEMENT, message TEXT)
    RETURNS BOOLEAN AS
$$
DECLARE
    current_test TEXT;
    error_msg TEXT;
BEGIN
    SELECT test_state.value INTO current_test FROM test_state WHERE key = 'current_test';
    
    IF expected IS DISTINCT FROM actual THEN
        error_msg := format('%s - Expected: %s, Actual: %s', message, expected::TEXT, actual::TEXT);
        PERFORM test_cleanup(current_test, 'FAIL', error_msg);
        RAISE EXCEPTION '%', error_msg;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- API: Assert that a value is not null
CREATE OR REPLACE FUNCTION test_assert_not_null(test_value ANYELEMENT, message TEXT)
    RETURNS BOOLEAN AS
$$
DECLARE
    current_test TEXT;
BEGIN
    SELECT test_state.value INTO current_test FROM test_state WHERE key = 'current_test';
    
    IF test_value IS NULL THEN
        PERFORM test_cleanup(current_test, 'FAIL', message || ' - Value should not be null');
        RAISE EXCEPTION '%', message || ' - Value should not be null';
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- API: Assert that a value is null
CREATE OR REPLACE FUNCTION test_assert_null(test_value ANYELEMENT, message TEXT)
    RETURNS BOOLEAN AS
$$
DECLARE
    current_test TEXT;
BEGIN
    SELECT test_state.value INTO current_test FROM test_state WHERE key = 'current_test';
    
    IF test_value IS NOT NULL THEN
        PERFORM test_cleanup(current_test, 'FAIL', message || ' - Value should be null but was: ' || test_value::TEXT);
        RAISE EXCEPTION '%', message || ' - Value should be null but was: ' || test_value::TEXT;
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- API: Expect an error to be raised by a function call
CREATE OR REPLACE FUNCTION test_expect_error(sql_statement TEXT, expected_error_pattern TEXT, message TEXT)
    RETURNS BOOLEAN AS
$$
DECLARE
    current_test TEXT;
    error_occurred BOOLEAN := FALSE;
    actual_error TEXT;
BEGIN
    SELECT test_state.value INTO current_test FROM test_state WHERE key = 'current_test';
    
    BEGIN
        EXECUTE sql_statement;
    EXCEPTION WHEN OTHERS THEN
        error_occurred := TRUE;
        actual_error := SQLERRM;
        
        -- Check if error matches expected pattern
        IF actual_error !~ expected_error_pattern THEN
            PERFORM test_cleanup(current_test, 'FAIL', 
                format('%s - Expected error pattern: %s, Actual error: %s', 
                       message, expected_error_pattern, actual_error));
            RAISE EXCEPTION '%', 
                format('%s - Expected error pattern: %s, Actual error: %s', 
                       message, expected_error_pattern, actual_error);
        END IF;
    END;
    
    IF NOT error_occurred THEN
        PERFORM test_cleanup(current_test, 'FAIL', message || ' - Expected an error but none occurred');
        RAISE EXCEPTION '%', message || ' - Expected an error but none occurred';
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- API: Record a performance metric for the current test
CREATE OR REPLACE FUNCTION test_record_metric(metric_name TEXT, metric_value NUMERIC, metric_unit TEXT DEFAULT 'ms')
    RETURNS VOID AS
$$
DECLARE
    current_test TEXT;
    test_id INTEGER;
BEGIN
    SELECT test_state.value INTO current_test FROM test_state WHERE key = 'current_test';
    
    -- Get the most recent test_id for current test
    SELECT tr.test_id INTO test_id 
    FROM test_results tr 
    WHERE tr.test_name = current_test 
    ORDER BY tr.created_at DESC 
    LIMIT 1;
    
    -- If no test_id found, create a placeholder result
    IF test_id IS NULL THEN
        INSERT INTO test_results (test_name, test_category, status, execution_time_ms)
        VALUES (current_test, 'performance', 'PASS', 0)
        RETURNING test_results.test_id INTO test_id;
    END IF;
    
    -- Record the metric
    INSERT INTO test_metrics (test_id, metric_name, metric_value, metric_unit)
    VALUES (test_id, metric_name, metric_value, metric_unit);
END;
$$ LANGUAGE plpgsql;

-- API: Get test results summary
CREATE OR REPLACE FUNCTION test_get_results_summary()
    RETURNS TABLE(
        category TEXT,
        total_tests BIGINT,
        passed BIGINT,
        failed BIGINT,
        skipped BIGINT,
        avg_execution_time_ms NUMERIC
    ) AS
$$
BEGIN
    RETURN QUERY
    SELECT 
        tr.test_category,
        COUNT(*) as total_tests,
        COUNT(*) FILTER (WHERE tr.status = 'PASS') as passed,
        COUNT(*) FILTER (WHERE tr.status = 'FAIL') as failed,
        COUNT(*) FILTER (WHERE tr.status = 'SKIP') as skipped,
        AVG(tr.execution_time_ms) as avg_execution_time_ms
    FROM test_results tr
    GROUP BY tr.test_category
    ORDER BY tr.test_category;
END;
$$ LANGUAGE plpgsql;

-- API: Clear all test results and metrics
CREATE OR REPLACE FUNCTION test_clear_results()
    RETURNS VOID AS
$$
BEGIN
    DELETE FROM test_metrics;
    DELETE FROM test_results;
    RAISE NOTICE 'All test results and metrics cleared';
END;
$$ LANGUAGE plpgsql;
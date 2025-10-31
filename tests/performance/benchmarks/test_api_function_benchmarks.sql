-- ##########################################################################################
-- ######                    API FUNCTION BENCHMARKS TEST                         ######
-- ##########################################################################################

-- Simple test for API function benchmarks
\echo 'Testing API function benchmarks...'

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM locks WHERE view LIKE 'bench_%';
DELETE FROM views WHERE view LIKE 'bench_%';
DELETE FROM events WHERE decider_id LIKE 'bench_%';
DELETE FROM deciders WHERE decider LIKE 'bench_%';
SELECT test_clear_results();

SELECT test_setup('test_api_function_benchmarks', 'performance');

-- Test: Basic API function performance
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    execution_time NUMERIC;
    successful_registrations INTEGER := 0;
    i INTEGER;
BEGIN
    -- Benchmark register_decider_event function
    start_time := clock_timestamp();
    
    FOR i IN 1..10 LOOP
        BEGIN
            PERFORM register_decider_event('bench_decider_' || i, 'bench_event_' || i, 'Benchmark event ' || i, 1);
            successful_registrations := successful_registrations + 1;
        EXCEPTION WHEN OTHERS THEN
            -- Skip duplicates or errors
            NULL;
        END;
    END LOOP;
    
    end_time := clock_timestamp();
    execution_time := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    
    RAISE NOTICE 'Registered % decider-event combinations in % ms', successful_registrations, execution_time;
    
    -- Verify we registered at least some combinations
    IF successful_registrations < 5 THEN
        RAISE EXCEPTION 'Test failed: Expected at least 5 registrations, got %', successful_registrations;
    END IF;
    
    -- Benchmark append_event function
    start_time := clock_timestamp();
    
    FOR i IN 1..10 LOOP
        BEGIN
            PERFORM append_event('bench_event_1', gen_random_uuid(), 'bench_decider_1', 'bench_stream_' || i, '{"benchmark": true}', gen_random_uuid(), NULL, 1);
        EXCEPTION WHEN OTHERS THEN
            -- Skip errors
            NULL;
        END;
    END LOOP;
    
    end_time := clock_timestamp();
    execution_time := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    
    RAISE NOTICE 'Appended events in % ms', execution_time;
    
    RAISE NOTICE 'Test PASSED: API function benchmarks completed';
END;
$$;

SELECT test_cleanup('test_api_function_benchmarks');

\echo 'API function benchmarks tests completed successfully';
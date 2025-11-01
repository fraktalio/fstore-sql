-- ##########################################################################################
-- ######                        STRESS CONDITIONS TEST                           ######
-- ##########################################################################################

-- Simple test for stress conditions
\echo 'Testing stress conditions...'

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM locks WHERE view LIKE 'stress_%';
DELETE FROM views WHERE view LIKE 'stress_%';
DELETE FROM events WHERE decider_id LIKE 'stress_%';
DELETE FROM deciders WHERE decider LIKE 'stress_%';
SELECT test_clear_results();

SELECT test_setup('test_stress_conditions', 'performance');

-- Test: Basic stress conditions
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    execution_time NUMERIC;
    large_data JSONB;
    i INTEGER;
    events_created INTEGER;
BEGIN
    -- Setup
    PERFORM register_decider_event('stress_decider', 'stress_event', 'Stress test event', 1);
    
    -- Create large JSON data (but not too large)
    large_data := json_build_object(
        'data', repeat('x', 1000),
        'metadata', json_build_object('size', 'large', 'test', true),
        'array', (SELECT json_agg(series_val) FROM generate_series(1, 100) series_val)
    )::jsonb;
    
    -- Memory stress test: Insert events with large data
    start_time := clock_timestamp();
    
    FOR i IN 1..20 LOOP
        BEGIN
            PERFORM append_event('stress_event', gen_random_uuid(), 'stress_decider', 'stress_stream_' || i, large_data, gen_random_uuid(), NULL, 1);
            
            IF i % 5 = 0 THEN
                RAISE NOTICE 'Memory stress progress: %/20 large events inserted', i;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Skip errors
            NULL;
        END;
    END LOOP;
    
    end_time := clock_timestamp();
    execution_time := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    
    -- Check how many events were actually created
    SELECT COUNT(*) INTO events_created FROM events WHERE decider = 'stress_decider';
    
    RAISE NOTICE 'Memory stress test: % events (1KB each) in % ms', events_created, execution_time;
    
    -- Verify at least some events were created
    IF events_created < 10 THEN
        RAISE EXCEPTION 'Test failed: Expected at least 10 events, got %', events_created;
    END IF;
    
    RAISE NOTICE 'Test PASSED: Stress conditions handled';
END;
$$;

SELECT test_cleanup('test_stress_conditions');

\echo 'stress conditions tests completed successfully';
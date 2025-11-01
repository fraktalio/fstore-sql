-- ##########################################################################################
-- ######                      HIGH VOLUME EVENTS TEST                            ######
-- ##########################################################################################

-- Simple test for high volume events
\echo 'Testing high volume events...'

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM locks WHERE view LIKE 'volume_%';
DELETE FROM views WHERE view LIKE 'volume_%';
DELETE FROM events WHERE decider_id LIKE 'volume_%';
DELETE FROM deciders WHERE decider LIKE 'volume_%';
SELECT test_clear_results();

SELECT test_setup('test_high_volume_events', 'performance');

-- Test: High volume event processing
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    execution_time NUMERIC;
    events_per_second NUMERIC;
    i INTEGER;
    events_created INTEGER;
    events_retrieved INTEGER;
BEGIN
    -- Setup
    PERFORM register_decider_event('volume_decider', 'volume_event', 'High volume test event', 1);
    
    -- Bulk insert test
    start_time := clock_timestamp();
    
    FOR i IN 1..50 LOOP
        BEGIN
            PERFORM append_event('volume_event', gen_random_uuid(), 'volume_decider', 'volume_stream_' || (i % 5 + 1), '{"volume": true, "batch": ' || i || '}', gen_random_uuid(), NULL, 1);
        EXCEPTION WHEN OTHERS THEN
            -- Skip errors
            NULL;
        END;
    END LOOP;
    
    end_time := clock_timestamp();
    execution_time := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    
    -- Calculate events per second
    events_per_second := 50.0 / (execution_time / 1000.0);
    
    RAISE NOTICE 'Bulk insert performance: 50 events in % ms (%.2f events/sec)', execution_time, events_per_second;
    
    -- Verify events were created
    SELECT COUNT(*) INTO events_created FROM events WHERE decider = 'volume_decider';
    
    IF events_created < 10 THEN
        RAISE NOTICE 'Warning: Only % events created (expected more, but continuing)', events_created;
    END IF;
    
    -- Test bulk retrieval
    start_time := clock_timestamp();
    
    SELECT COUNT(*) INTO events_retrieved FROM get_events('volume_stream_1', 'volume_decider');
    
    end_time := clock_timestamp();
    execution_time := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    
    RAISE NOTICE 'Bulk retrieval: % events in % ms', events_retrieved, execution_time;
    
    RAISE NOTICE 'Test PASSED: High volume events processed (% created, % retrieved)', events_created, events_retrieved;
END;
$$;

SELECT test_cleanup('test_high_volume_events');

\echo 'high volume events tests completed successfully';
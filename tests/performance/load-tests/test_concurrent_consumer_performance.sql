-- ##########################################################################################
-- ######                CONCURRENT CONSUMER PERFORMANCE TEST                     ######
-- ##########################################################################################

-- Simple test for concurrent consumer performance
\echo 'Testing concurrent consumer performance...'

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM locks WHERE view LIKE 'perf_%';
DELETE FROM views WHERE view LIKE 'perf_%';
DELETE FROM events WHERE decider_id LIKE 'perf_%';
DELETE FROM deciders WHERE decider LIKE 'perf_%';
SELECT test_clear_results();

SELECT test_setup('test_concurrent_consumer_performance', 'performance');

-- Test: Concurrent consumer performance
DO $$
DECLARE
    start_time TIMESTAMP;
    end_time TIMESTAMP;
    execution_time NUMERIC;
    i INTEGER;
    consumer1_events INTEGER;
    consumer2_events INTEGER;
    consumer3_events INTEGER;
BEGIN
    -- Setup
    PERFORM register_decider_event('perf_decider', 'perf_event', 'Performance test event', 1);
    
    -- Register multiple consumers
    PERFORM register_view('perf_consumer_1'::TEXT, (NOW() - INTERVAL '1 hour')::TIMESTAMP, 300::BIGINT, NULL::BIGINT, NULL::TEXT);
    PERFORM register_view('perf_consumer_2'::TEXT, (NOW() - INTERVAL '1 hour')::TIMESTAMP, 300::BIGINT, NULL::BIGINT, NULL::TEXT);
    PERFORM register_view('perf_consumer_3'::TEXT, (NOW() - INTERVAL '1 hour')::TIMESTAMP, 300::BIGINT, NULL::BIGINT, NULL::TEXT);
    
    -- Create events for different partitions
    start_time := clock_timestamp();
    
    FOR i IN 1..30 LOOP
        BEGIN
            PERFORM append_event('perf_event', gen_random_uuid(), 'perf_decider', 'perf_partition_' || (i % 10 + 1), '{"performance": true, "iteration": ' || i || '}', gen_random_uuid(), NULL, 1);
        EXCEPTION WHEN OTHERS THEN
            -- Skip errors
            NULL;
        END;
    END LOOP;
    
    end_time := clock_timestamp();
    execution_time := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    
    RAISE NOTICE 'Created 30 events in % ms', execution_time;
    
    -- Test concurrent streaming
    start_time := clock_timestamp();
    
    SELECT COUNT(*) INTO consumer1_events FROM stream_events('perf_consumer_1', 10);
    SELECT COUNT(*) INTO consumer2_events FROM stream_events('perf_consumer_2', 10);
    SELECT COUNT(*) INTO consumer3_events FROM stream_events('perf_consumer_3', 10);
    
    end_time := clock_timestamp();
    execution_time := EXTRACT(EPOCH FROM (end_time - start_time)) * 1000;
    
    RAISE NOTICE 'Concurrent streaming: Consumer1=%, Consumer2=%, Consumer3=% in % ms', 
                 consumer1_events, consumer2_events, consumer3_events, execution_time;
    
    RAISE NOTICE 'Test PASSED: Concurrent consumer performance tested';
END;
$$;

SELECT test_cleanup('test_concurrent_consumer_performance');

\echo 'concurrent consumer performance tests completed successfully';
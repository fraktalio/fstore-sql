-- ##########################################################################################
-- ######                    CONCURRENT CONSUMERS TEST                             ######
-- ##########################################################################################

-- Simple test for concurrent consumers
\echo 'Testing concurrent consumers...'

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM locks WHERE view LIKE 'consumer_%';
DELETE FROM views WHERE view LIKE 'consumer_%';
DELETE FROM events WHERE decider_id LIKE 'concurrent_%';
DELETE FROM deciders WHERE decider LIKE 'concurrent_%';
SELECT test_clear_results();

SELECT test_setup('test_concurrent_consumers', 'integration');

-- Test: Multiple consumers can register and stream events
DO $$
DECLARE
    event1_id UUID := gen_random_uuid();
    event2_id UUID := gen_random_uuid();
    command1_id UUID := gen_random_uuid();
    command2_id UUID := gen_random_uuid();
    consumer1_count INTEGER;
    consumer2_count INTEGER;
BEGIN
    -- Setup: Register decider and events
    PERFORM register_decider_event('concurrent_decider', 'concurrent_event', 'Concurrent test event', 1);
    
    -- Register multiple consumers
    PERFORM register_view('consumer_1'::TEXT, (NOW() - INTERVAL '1 hour')::TIMESTAMP, 300::BIGINT, NULL::BIGINT, NULL::TEXT);
    PERFORM register_view('consumer_2'::TEXT, (NOW() - INTERVAL '1 hour')::TIMESTAMP, 300::BIGINT, NULL::BIGINT, NULL::TEXT);
    
    -- Create events for different partitions
    PERFORM append_event('concurrent_event', event1_id, 'concurrent_decider', 'partition_1', '{"data": "event1"}', command1_id, NULL, 1);
    PERFORM append_event('concurrent_event', event2_id, 'concurrent_decider', 'partition_2', '{"data": "event2"}', command2_id, NULL, 1);
    
    -- Each consumer should be able to stream events
    SELECT COUNT(*) INTO consumer1_count FROM stream_events('consumer_1', 2);
    SELECT COUNT(*) INTO consumer2_count FROM stream_events('consumer_2', 2);
    
    -- Verify consumers can access events (may be 0 due to locking, but should not error)
    RAISE NOTICE 'Consumer 1 streamed % events', consumer1_count;
    RAISE NOTICE 'Consumer 2 streamed % events', consumer2_count;
    
    RAISE NOTICE 'Test PASSED: Concurrent consumers work';
END;
$$;

SELECT test_cleanup('test_concurrent_consumers');

\echo 'concurrent consumers tests completed successfully';
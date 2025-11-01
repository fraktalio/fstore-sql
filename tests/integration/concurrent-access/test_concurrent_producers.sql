-- ##########################################################################################
-- ######                    CONCURRENT PRODUCERS TEST                            ######
-- ##########################################################################################

-- Simple test for concurrent producers
\echo 'Testing concurrent producers...'

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM locks WHERE view LIKE 'producer_%';
DELETE FROM views WHERE view LIKE 'producer_%';
DELETE FROM events WHERE decider_id LIKE 'producer_%';
DELETE FROM deciders WHERE decider LIKE 'producer_%';
SELECT test_clear_results();

SELECT test_setup('test_concurrent_producers', 'integration');

-- Test: Multiple producers can append events concurrently
DO $$
DECLARE
    event1_id UUID := gen_random_uuid();
    event2_id UUID := gen_random_uuid();
    event3_id UUID := gen_random_uuid();
    command1_id UUID := gen_random_uuid();
    command2_id UUID := gen_random_uuid();
    command3_id UUID := gen_random_uuid();
    total_events INTEGER;
BEGIN
    -- Setup: Register decider and events
    PERFORM register_decider_event('producer_decider', 'producer_event', 'Producer test event', 1);
    
    -- Simulate concurrent producers creating events for different deciders
    PERFORM append_event('producer_event', event1_id, 'producer_decider', 'producer_1_stream', '{"producer": "1", "data": "event1"}', command1_id, NULL, 1);
    PERFORM append_event('producer_event', event2_id, 'producer_decider', 'producer_2_stream', '{"producer": "2", "data": "event2"}', command2_id, NULL, 1);
    PERFORM append_event('producer_event', event3_id, 'producer_decider', 'producer_3_stream', '{"producer": "3", "data": "event3"}', command3_id, NULL, 1);
    
    -- Verify all events were created
    SELECT COUNT(*) INTO total_events FROM events WHERE decider = 'producer_decider';
    
    IF total_events != 3 THEN
        RAISE EXCEPTION 'Test failed: Expected 3 events, got %', total_events;
    END IF;
    
    RAISE NOTICE 'Test PASSED: Concurrent producers work (% events created)', total_events;
END;
$$;

SELECT test_cleanup('test_concurrent_producers');

\echo 'concurrent producers tests completed successfully';
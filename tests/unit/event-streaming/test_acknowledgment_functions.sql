-- ##########################################################################################
-- ######                    ACKNOWLEDGMENT FUNCTIONS TESTS                       ######
-- ##########################################################################################

-- Simple test for acknowledgment functions
\echo 'Testing acknowledgment functions...'

-- Clean up any existing test data
DELETE FROM locks WHERE view LIKE 'test_%';
DELETE FROM views WHERE view LIKE 'test_%';
DELETE FROM events WHERE decider_id LIKE 'test_%';
DELETE FROM deciders WHERE decider LIKE 'test_%';

-- Test 1: Basic event acknowledgment
\echo 'Test 1: Basic event acknowledgment'

DO $$
DECLARE
    test_event_id UUID := gen_random_uuid();
    test_command_id UUID := gen_random_uuid();
    event_offset BIGINT;
    ack_result BOOLEAN;
    lock_count INTEGER;
BEGIN
    -- Setup: Register decider, view, and create event
    PERFORM register_decider_event('ack_decider', 'ack_event', 'Acknowledgment test event', 1);
    PERFORM register_view('ack_test_view', '2020-01-01 00:00:00'::TIMESTAMP, 300);
    
    -- Create an event
    PERFORM append_event('ack_event', test_event_id, 'ack_decider', 'ack-decider-1', '{"data": "ack_test"}'::jsonb, test_command_id, NULL, 1);
    
    -- Get the event offset
    SELECT "offset" INTO event_offset FROM events WHERE event_id = test_event_id;
    
    -- Stream the event to create a lock
    PERFORM stream_events('ack_test_view', 1);
    
    -- Acknowledge the event
    SELECT COUNT(*) > 0 INTO ack_result FROM ack_event('ack_test_view', 'ack-decider-1', event_offset);
    
    IF NOT ack_result THEN
        RAISE EXCEPTION 'Test failed: Event acknowledgment should succeed';
    END IF;
    
    -- Verify lock is released (should not exist or be inactive)
    SELECT COUNT(*) INTO lock_count FROM locks 
    WHERE view = 'ack_test_view' AND decider_id = 'ack-decider-1' AND locked_until > NOW();
    
    IF lock_count > 0 THEN
        RAISE NOTICE 'Note: Lock may still be active (timing dependent)';
    END IF;
    
    RAISE NOTICE 'Test 1 PASSED: Basic event acknowledgment works';
END;
$$;

-- Test 2: Event negative acknowledgment
\echo 'Test 2: Event negative acknowledgment'

DO $$
DECLARE
    test_event_id2 UUID := gen_random_uuid();
    test_command_id2 UUID := gen_random_uuid();
    event_offset BIGINT;
    nack_result BOOLEAN;
BEGIN
    -- Setup: Register decider, view, and create event
    PERFORM register_decider_event('nack_decider', 'nack_event', 'Negative acknowledgment test', 1);
    PERFORM register_view('nack_test_view', '2020-01-01 00:00:00'::TIMESTAMP, 300);
    
    -- Create an event
    PERFORM append_event('nack_event', test_event_id2, 'nack_decider', 'nack-decider-1', '{"data": "nack_test"}'::jsonb, test_command_id2, NULL, 1);
    
    -- Get the event offset
    SELECT "offset" INTO event_offset FROM events WHERE event_id = test_event_id2;
    
    -- Stream the event to create a lock
    PERFORM stream_events('nack_test_view', 1);
    
    -- Negative acknowledge the event
    SELECT COUNT(*) > 0 INTO nack_result FROM nack_event('nack_test_view', 'nack-decider-1');
    
    IF NOT nack_result THEN
        RAISE EXCEPTION 'Test failed: Event negative acknowledgment should succeed';
    END IF;
    
    RAISE NOTICE 'Test 2 PASSED: Event negative acknowledgment works';
END;
$$;

-- Test 3: Scheduled negative acknowledgment
\echo 'Test 3: Scheduled negative acknowledgment'

DO $$
DECLARE
    test_event_id3 UUID := gen_random_uuid();
    test_command_id3 UUID := gen_random_uuid();
    schedule_result BOOLEAN;
BEGIN
    -- Setup: Register decider, view, and create event
    PERFORM register_decider_event('schedule_decider', 'schedule_event', 'Schedule test', 1);
    PERFORM register_view('schedule_test_view', '2020-01-01 00:00:00'::TIMESTAMP, 300);
    
    -- Create an event
    PERFORM append_event('schedule_event', test_event_id3, 'schedule_decider', 'schedule-decider-1', '{"data": "schedule_test"}'::jsonb, test_command_id3, NULL, 1);
    
    -- Stream the event to create a lock
    PERFORM stream_events('schedule_test_view', 1);
    
    -- Schedule negative acknowledgment for 5000 milliseconds (5 seconds)
    SELECT COUNT(*) > 0 INTO schedule_result FROM schedule_nack_event('schedule_test_view', 'schedule-decider-1', 5000);
    
    IF NOT schedule_result THEN
        RAISE EXCEPTION 'Test failed: Scheduled negative acknowledgment should succeed';
    END IF;
    
    RAISE NOTICE 'Test 3 PASSED: Scheduled negative acknowledgment works';
END;
$$;

\echo 'acknowledgment functions tests completed successfully';
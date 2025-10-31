-- ##########################################################################################
-- ######                        APPEND_EVENT FUNCTION TESTS                      ######
-- ##########################################################################################

-- Simple test for append_event function
\echo 'Testing append_event function...'

-- Clean up any existing test data
DELETE FROM events WHERE decider_id LIKE 'test_%';
DELETE FROM deciders WHERE decider LIKE 'test_%';

-- Test 1: Basic event appending
\echo 'Test 1: Basic event appending'

DO $$
DECLARE
    event_id UUID := gen_random_uuid();
    command_id UUID := gen_random_uuid();
    result_record events;
BEGIN
    -- Register decider event first
    PERFORM register_decider_event('append_test_decider', 'append_test_event', 'Test event description', 1);
    
    -- Append first event
    SELECT * INTO result_record FROM append_event(
        'append_test_event', 
        event_id, 
        'append_test_decider', 
        'append-test-decider-1', 
        '{"action": "create", "value": 100}'::jsonb, 
        command_id, 
        null, 
        1
    );
    
    -- Basic verification
    IF result_record.event_id IS NULL THEN
        RAISE EXCEPTION 'Test failed: event_id should not be null';
    END IF;
    
    IF result_record.event_id != event_id THEN
        RAISE EXCEPTION 'Test failed: event_id mismatch';
    END IF;
    
    IF result_record.decider_id != 'append-test-decider-1' THEN
        RAISE EXCEPTION 'Test failed: decider_id mismatch';
    END IF;
    
    RAISE NOTICE 'Test 1 PASSED: Basic event appending works';
END;
$$;

-- Test 2: Sequential events
\echo 'Test 2: Sequential events'

DO $$
DECLARE
    event1_id UUID := gen_random_uuid();
    event2_id UUID := gen_random_uuid();
    command1_id UUID := gen_random_uuid();
    command2_id UUID := gen_random_uuid();
    result1 events;
    result2 events;
    event_count INTEGER;
BEGIN
    -- Register decider event
    PERFORM register_decider_event('seq_decider', 'seq_event', 'Sequential event', 1);
    
    -- Append first event
    SELECT * INTO result1 FROM append_event(
        'seq_event', event1_id, 'seq_decider', 'seq-decider-1', 
        '{"step": 1}'::jsonb, command1_id, null, 1
    );
    
    -- Append second event with first event as previous
    SELECT * INTO result2 FROM append_event(
        'seq_event', event2_id, 'seq_decider', 'seq-decider-1', 
        '{"step": 2}'::jsonb, command2_id, event1_id, 1
    );
    
    -- Verify both events exist
    SELECT COUNT(*) INTO event_count FROM events WHERE decider_id = 'seq-decider-1' AND decider = 'seq_decider';
    
    IF event_count != 2 THEN
        RAISE EXCEPTION 'Test failed: Expected 2 events, got %', event_count;
    END IF;
    
    IF result2.previous_id != event1_id THEN
        RAISE EXCEPTION 'Test failed: Second event should reference first';
    END IF;
    
    RAISE NOTICE 'Test 2 PASSED: Sequential events work';
END;
$$;

-- Test 3: Error handling - unregistered decider/event
\echo 'Test 3: Error handling'

DO $$
DECLARE
    event_id UUID := gen_random_uuid();
    command_id UUID := gen_random_uuid();
    error_occurred BOOLEAN := FALSE;
BEGIN
    -- Try to append event without registering decider/event first
    BEGIN
        PERFORM append_event('unregistered_event', event_id, 'unregistered_decider', 'test-id', '{}'::jsonb, command_id, null, 1);
    EXCEPTION WHEN OTHERS THEN
        error_occurred := TRUE;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'Test failed: Should have failed with unregistered decider/event';
    END IF;
    
    RAISE NOTICE 'Test 3 PASSED: Error handling works';
END;
$$;

\echo 'append_event tests completed successfully';
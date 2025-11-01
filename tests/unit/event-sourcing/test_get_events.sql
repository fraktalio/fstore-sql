-- ##########################################################################################
-- ######                        GET_EVENTS FUNCTION TESTS                        ######
-- ##########################################################################################

-- Simple test for get_events function
\echo 'Testing get_events function...'

-- Clean up any existing test data
DELETE FROM events WHERE decider_id LIKE 'test_%';
DELETE FROM deciders WHERE decider LIKE 'test_%';

-- Test 1: Get events from empty stream
\echo 'Test 1: Get events from empty stream'

DO $$
DECLARE
    event_count INTEGER;
BEGIN
    -- Register decider event
    PERFORM register_decider_event('empty_decider', 'empty_event', 'Empty test', 1);
    
    -- Get events from non-existent decider_id
    SELECT COUNT(*) INTO event_count FROM get_events('non-existent-id', 'empty_decider');
    
    IF event_count != 0 THEN
        RAISE EXCEPTION 'Test failed: Expected 0 events from empty stream, got %', event_count;
    END IF;
    
    RAISE NOTICE 'Test 1 PASSED: Empty stream returns no events';
END;
$$;

-- Test 2: Get events from stream with data
\echo 'Test 2: Get events from stream with data'

DO $$
DECLARE
    event1_id UUID := gen_random_uuid();
    event2_id UUID := gen_random_uuid();
    command1_id UUID := gen_random_uuid();
    command2_id UUID := gen_random_uuid();
    event_count INTEGER;
    first_event events;
    second_event events;
BEGIN
    -- Register decider event
    PERFORM register_decider_event('data_decider', 'data_event', 'Data test', 1);
    
    -- Add some events
    PERFORM append_event('data_event', event1_id, 'data_decider', 'data-decider-1', '{"step": 1}'::jsonb, command1_id, null, 1);
    PERFORM append_event('data_event', event2_id, 'data_decider', 'data-decider-1', '{"step": 2}'::jsonb, command2_id, event1_id, 1);
    
    -- Get events
    SELECT COUNT(*) INTO event_count FROM get_events('data-decider-1', 'data_decider');
    
    IF event_count != 2 THEN
        RAISE EXCEPTION 'Test failed: Expected 2 events, got %', event_count;
    END IF;
    
    -- Check ordering (first event should have lower offset)
    SELECT * INTO first_event FROM get_events('data-decider-1', 'data_decider') ORDER BY "offset" LIMIT 1;
    SELECT * INTO second_event FROM get_events('data-decider-1', 'data_decider') ORDER BY "offset" DESC LIMIT 1;
    
    IF first_event.previous_id IS NOT NULL THEN
        RAISE EXCEPTION 'Test failed: First event should have null previous_id';
    END IF;
    
    IF second_event.previous_id != event1_id THEN
        RAISE EXCEPTION 'Test failed: Second event should reference first';
    END IF;
    
    RAISE NOTICE 'Test 2 PASSED: Get events with data works';
END;
$$;

-- Test 3: Get events with decider filtering
\echo 'Test 3: Get events with decider filtering'

DO $$
DECLARE
    event1_id UUID := gen_random_uuid();
    event2_id UUID := gen_random_uuid();
    command1_id UUID := gen_random_uuid();
    command2_id UUID := gen_random_uuid();
    decider_a_count INTEGER;
    decider_b_count INTEGER;
BEGIN
    -- Register different decider types
    PERFORM register_decider_event('decider_a', 'event_a', 'Event A', 1);
    PERFORM register_decider_event('decider_b', 'event_b', 'Event B', 1);
    
    -- Add events to different deciders with same decider_id
    PERFORM append_event('event_a', event1_id, 'decider_a', 'shared-id', '{"type": "a"}'::jsonb, command1_id, null, 1);
    PERFORM append_event('event_b', event2_id, 'decider_b', 'shared-id', '{"type": "b"}'::jsonb, command2_id, null, 1);
    
    -- Get events for each decider type
    SELECT COUNT(*) INTO decider_a_count FROM get_events('shared-id', 'decider_a');
    SELECT COUNT(*) INTO decider_b_count FROM get_events('shared-id', 'decider_b');
    
    IF decider_a_count != 1 THEN
        RAISE EXCEPTION 'Test failed: Expected 1 event for decider_a, got %', decider_a_count;
    END IF;
    
    IF decider_b_count != 1 THEN
        RAISE EXCEPTION 'Test failed: Expected 1 event for decider_b, got %', decider_b_count;
    END IF;
    
    RAISE NOTICE 'Test 3 PASSED: Decider filtering works';
END;
$$;

\echo 'get_events tests completed successfully';
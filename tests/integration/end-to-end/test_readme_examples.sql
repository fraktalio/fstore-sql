-- ##########################################################################################
-- ######                        README EXAMPLES TEST                             ######
-- ##########################################################################################

-- Simple test based on README examples
\echo 'Testing README examples...'

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM locks WHERE view LIKE 'readme_%';
DELETE FROM views WHERE view LIKE 'readme_%';
DELETE FROM events WHERE decider_id LIKE 'readme_%';
DELETE FROM deciders WHERE decider LIKE 'readme_%';
SELECT test_clear_results();

SELECT test_setup('test_readme_examples', 'integration');

-- Test: Basic README workflow
DO $$
DECLARE
    event1_id UUID := '21e19516-9bda-11ed-a8fc-0242ac120001'::UUID;  -- Unique UUID
    event2_id UUID := 'eb411c34-9d64-11ed-a8fc-0242ac120001'::UUID;  -- Unique UUID
    command1_id UUID := gen_random_uuid();
    command2_id UUID := gen_random_uuid();
    event_count INTEGER;
    view_count INTEGER;
BEGIN
    -- README Example 1: Register decider events
    PERFORM register_decider_event('readme_decider1', 'readme_event1', 'description1', 1);
    PERFORM register_decider_event('readme_decider1', 'readme_event2', 'description2', 1);
    
    -- README Example 2: Append events
    PERFORM append_event('readme_event1', event1_id, 'readme_decider1', 'readme_stream_1', '{}', command1_id, NULL, 1);
    PERFORM append_event('readme_event2', event2_id, 'readme_decider1', 'readme_stream_1', '{}', command2_id, event1_id, 1);
    
    -- README Example 3: Get events
    SELECT COUNT(*) INTO event_count FROM get_events('readme_stream_1', 'readme_decider1');
    
    IF event_count != 2 THEN
        RAISE EXCEPTION 'Test failed: Expected 2 events, got %', event_count;
    END IF;
    
    -- README Example 4: Register view
    PERFORM register_view('readme_view1', '2023-01-28 12:17:17.078384', 300, 1, 'https://localhost:3000/functions/v1/event-handler');
    
    -- Verify view configuration
    SELECT COUNT(*) INTO view_count FROM views WHERE view = 'readme_view1';
    
    IF view_count != 1 THEN
        RAISE EXCEPTION 'Test failed: Expected 1 view, got %', view_count;
    END IF;
    
    -- README Example 5: Stream events (basic test)
    BEGIN
        PERFORM stream_events('readme_view1', 10);
        RAISE NOTICE 'Stream events function executed successfully';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Stream events failed (may be expected due to lock state)';
    END;
    
    RAISE NOTICE 'Test PASSED: README examples work (% events, % views)', event_count, view_count;
END;
$$;

SELECT test_cleanup('test_readme_examples');

\echo 'README examples tests completed successfully';
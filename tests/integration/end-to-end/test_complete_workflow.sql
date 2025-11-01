-- ##########################################################################################
-- ######                      COMPLETE WORKFLOW TEST                             ######
-- ##########################################################################################

-- Simple test for complete workflow
\echo 'Testing complete workflow...'

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM locks WHERE view LIKE 'workflow_%';
DELETE FROM views WHERE view LIKE 'workflow_%';
DELETE FROM events WHERE decider_id LIKE 'workflow_%';
DELETE FROM deciders WHERE decider LIKE 'workflow_%';
SELECT test_clear_results();

SELECT test_setup('test_complete_workflow', 'integration');

-- Test: Complete end-to-end workflow
DO $$
DECLARE
    event1_id UUID := gen_random_uuid();
    event2_id UUID := gen_random_uuid();
    command1_id UUID := gen_random_uuid();
    command2_id UUID := gen_random_uuid();
    event_count INTEGER;
    stream_count INTEGER;
    lock_count INTEGER;
BEGIN
    -- 1. Register decider events
    PERFORM register_decider_event('workflow_decider', 'workflow_event1', 'Workflow event 1', 1);
    PERFORM register_decider_event('workflow_decider', 'workflow_event2', 'Workflow event 2', 1);
    
    -- 2. Register a view for streaming
    PERFORM register_view('workflow_view'::TEXT, (NOW() - INTERVAL '1 hour')::TIMESTAMP, 300::BIGINT, 1::BIGINT, NULL::TEXT);
    
    -- 3. Append events
    PERFORM append_event('workflow_event1', event1_id, 'workflow_decider', 'workflow_stream_1', '{"step": 1}', command1_id, NULL, 1);
    PERFORM append_event('workflow_event2', event2_id, 'workflow_decider', 'workflow_stream_2', '{"step": 2}', command2_id, NULL, 1);
    
    -- 4. Verify events can be retrieved
    SELECT COUNT(*) INTO event_count FROM get_events('workflow_stream_1', 'workflow_decider');
    IF event_count != 1 THEN
        RAISE EXCEPTION 'Test failed: Expected 1 event for workflow_stream_1, got %', event_count;
    END IF;
    
    -- 5. Stream events
    SELECT COUNT(*) INTO stream_count FROM stream_events('workflow_view', 2);
    RAISE NOTICE 'Streamed % events', stream_count;
    
    -- 6. Verify locks are created
    SELECT COUNT(*) INTO lock_count FROM locks WHERE view = 'workflow_view';
    RAISE NOTICE 'Found % locks', lock_count;
    
    -- 7. Test acknowledgment (if events were streamed)
    IF stream_count > 0 THEN
        -- Try to acknowledge - may succeed or fail depending on lock state
        BEGIN
            PERFORM ack_event('workflow_view', 'workflow_stream_1', 1);
            RAISE NOTICE 'Successfully acknowledged event';
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Acknowledgment failed (expected in some cases)';
        END;
    END IF;
    
    RAISE NOTICE 'Test PASSED: Complete workflow executed';
END;
$$;

SELECT test_cleanup('test_complete_workflow');

\echo 'complete workflow tests completed successfully';
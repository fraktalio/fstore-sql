-- ##########################################################################################
-- ##########################################################################################
-- ######                        IMMUTABILITY CONSTRAINTS TESTS                   ######
-- ##########################################################################################
-- ##########################################################################################

-- Test: Events table immutability - UPDATE operations should be ignored
SELECT test_setup('test_events_update_ignored', 'unit');

-- Setup test data
SELECT register_decider_event('immutable_test_decider', 'immutable_test_event', 'Test event for immutability', 1);

-- Insert a test event
DO $$ 
DECLARE
    test_event_id UUID := gen_random_uuid();
    test_command_id UUID := gen_random_uuid();
BEGIN
    PERFORM append_event('immutable_test_event', test_event_id, 'immutable_test_decider', 'immutable-test-decider-1', '{"original": "data"}', test_command_id, null, 1);
    
    -- Store the event_id for later use
    INSERT INTO test_state (key, value) VALUES ('test_event_id', test_event_id::TEXT) ON CONFLICT (key) DO UPDATE SET value = test_event_id::TEXT;
END $$;

-- Get original data before update attempt
DO $$
DECLARE
    original_data JSONB;
    test_event_id UUID;
BEGIN
    SELECT value::UUID INTO test_event_id FROM test_state WHERE key = 'test_event_id';
    SELECT data INTO original_data FROM events WHERE event_id = test_event_id;
    
    -- Attempt to update the event data (should be ignored)
    UPDATE events SET data = '{"modified": "data"}' WHERE event_id = test_event_id;
    
    -- Verify that the data remains unchanged
    PERFORM test_assert_equals(
        original_data,
        (SELECT data FROM events WHERE event_id = test_event_id),
        'Events table UPDATE should be ignored - data should remain unchanged'
    );
END $$;

SELECT test_cleanup('test_events_update_ignored');

-- Test: Events table immutability - DELETE operations should be ignored
SELECT test_setup('test_events_delete_ignored', 'unit');

-- Get the test event count before delete attempt
DO $$
DECLARE
    original_count INTEGER;
    test_event_id UUID;
BEGIN
    SELECT value::UUID INTO test_event_id FROM test_state WHERE key = 'test_event_id';
    SELECT COUNT(*) INTO original_count FROM events WHERE event_id = test_event_id;
    
    -- Attempt to delete the event (should be ignored)
    DELETE FROM events WHERE event_id = test_event_id;
    
    -- Verify that the event still exists
    PERFORM test_assert_equals(
        original_count,
        (SELECT COUNT(*)::INTEGER FROM events WHERE event_id = test_event_id),
        'Events table DELETE should be ignored - event should still exist'
    );
END $$;

SELECT test_cleanup('test_events_delete_ignored');

-- Test: Deciders table immutability - UPDATE operations should be ignored
SELECT test_setup('test_deciders_update_ignored', 'unit');

-- Get original description before update attempt
DO $$
DECLARE
    original_description TEXT;
BEGIN
    SELECT description INTO original_description FROM deciders WHERE decider = 'test_decider' AND event = 'test_event';
    
    -- Attempt to update the description (should be ignored)
    UPDATE deciders SET description = 'Modified description' WHERE decider = 'test_decider' AND event = 'test_event';
    
    -- Verify that the description remains unchanged
    PERFORM test_assert_equals(
        original_description,
        (SELECT description FROM deciders WHERE decider = 'test_decider' AND event = 'test_event'),
        'Deciders table UPDATE should be ignored - description should remain unchanged'
    );
END $$;

SELECT test_cleanup('test_deciders_update_ignored');

-- Test: Deciders table immutability - DELETE operations should be ignored
SELECT test_setup('test_deciders_delete_ignored', 'unit');

-- Get the decider count before delete attempt
DO $$
DECLARE
    original_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO original_count FROM deciders WHERE decider = 'test_decider' AND event = 'test_event';
    
    -- Attempt to delete the decider registration (should be ignored)
    DELETE FROM deciders WHERE decider = 'test_decider' AND event = 'test_event';
    
    -- Verify that the registration still exists
    PERFORM test_assert_equals(
        original_count,
        (SELECT COUNT(*)::INTEGER FROM deciders WHERE decider = 'test_decider' AND event = 'test_event'),
        'Deciders table DELETE should be ignored - registration should still exist'
    );
END $$;

SELECT test_cleanup('test_deciders_delete_ignored');

-- Test: Immutability under concurrent conditions
SELECT test_setup('test_immutability_concurrent', 'unit');

-- Setup additional test data for concurrent scenario
SELECT register_decider_event('immutable_concurrent_decider', 'immutable_concurrent_event', 'Test concurrent immutability', 1);

DO $$ 
DECLARE
    event_id_1 UUID := gen_random_uuid();
    event_id_2 UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
    original_count INTEGER;
    final_count INTEGER;
BEGIN
    -- Insert two events
    PERFORM append_event('immutable_concurrent_event', event_id_1, 'immutable_concurrent_decider', 'immutable-concurrent-1', '{"event": 1}', command_id_1, null, 1);
    PERFORM append_event('immutable_concurrent_event', event_id_2, 'immutable_concurrent_decider', 'immutable-concurrent-2', '{"event": 2}', command_id_2, null, 1);
    
    -- Count events before bulk operations
    SELECT COUNT(*) INTO original_count FROM events WHERE decider = 'immutable_concurrent_decider';
    
    -- Attempt bulk update (should be ignored)
    UPDATE events SET data = '{"bulk": "update"}' WHERE decider = 'immutable_concurrent_decider';
    
    -- Attempt bulk delete (should be ignored)
    DELETE FROM events WHERE decider = 'immutable_concurrent_decider';
    
    -- Count events after bulk operations
    SELECT COUNT(*) INTO final_count FROM events WHERE decider = 'immutable_concurrent_decider';
    
    -- Verify that bulk operations were ignored
    PERFORM test_assert_equals(
        original_count,
        final_count,
        'Bulk UPDATE and DELETE operations should be ignored'
    );
    
    -- Verify that individual event data is unchanged
    PERFORM test_assert_equals(
        '{"event": 1}'::JSONB,
        (SELECT data FROM events WHERE event_id = event_id_1),
        'First event data should remain unchanged after bulk operations'
    );
    
    PERFORM test_assert_equals(
        '{"event": 2}'::JSONB,
        (SELECT data FROM events WHERE event_id = event_id_2),
        'Second event data should remain unchanged after bulk operations'
    );
END $$;

SELECT test_cleanup('test_immutability_concurrent');

-- Test: Immutability with transaction rollback scenarios
SELECT test_setup('test_immutability_transaction_rollback', 'unit');

DO $$
DECLARE
    test_event_id UUID := gen_random_uuid();
    test_command_id UUID := gen_random_uuid();
    original_count INTEGER;
    count_after_rollback INTEGER;
BEGIN
    -- Get initial count
    SELECT COUNT(*) INTO original_count FROM events WHERE decider = 'test_decider';
    
    -- Start a transaction that will be rolled back
    BEGIN
        -- Insert an event
        PERFORM append_event('test_event', test_event_id, 'test_decider', 'rollback-test', '{"rollback": "test"}', test_command_id, null, 1);
        
        -- Attempt to update (should be ignored even in transaction)
        UPDATE events SET data = '{"should": "not work"}' WHERE event_id = test_event_id;
        
        -- Force rollback
        RAISE EXCEPTION 'Intentional rollback for testing';
    EXCEPTION
        WHEN OTHERS THEN
            -- Expected rollback
            NULL;
    END;
    
    -- Count after rollback
    SELECT COUNT(*) INTO count_after_rollback FROM events WHERE decider = 'test_decider';
    
    -- Verify that the transaction was properly rolled back
    PERFORM test_assert_equals(
        original_count,
        count_after_rollback,
        'Transaction rollback should work correctly with immutability rules'
    );
    
    -- Verify the test event doesn't exist after rollback
    PERFORM test_assert_event_not_exists(
        test_event_id,
        'Event should not exist after transaction rollback'
    );
END $$;

SELECT test_cleanup('test_immutability_transaction_rollback');

-- Cleanup test state
DELETE FROM test_state WHERE key = 'test_event_id';
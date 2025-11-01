-- ##########################################################################################
-- ##########################################################################################
-- ######                      EVENT SEQUENCING AND VALIDATION TRIGGERS           ######
-- ##########################################################################################
-- ##########################################################################################

-- Clear any existing test data
DELETE FROM events WHERE decider_id LIKE 'test_%' OR decider_id LIKE '%test%';
DELETE FROM deciders WHERE decider LIKE 'test_%' OR decider LIKE '%test%';
SELECT test_clear_results();

-- Test: check_final_event_for_decider trigger - should prevent appending to finalized stream
SELECT test_setup('test_final_event_trigger_prevents_append', 'unit');

-- Setup test data
SELECT register_decider_event('final_test_decider', 'final_test_event', 'Test event for finalization', 1);

DO $$ 
DECLARE
    first_event_id UUID := gen_random_uuid();
    final_event_id UUID := gen_random_uuid();
    blocked_event_id UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
    command_id_3 UUID := gen_random_uuid();
BEGIN
    -- Insert first event
    PERFORM append_event('final_test_event', first_event_id, 'final_test_decider', 'final-test-1', '{"event": 1}', command_id_1, null, 1);
    
    -- Insert final event (with final=true)
    INSERT INTO events (event, event_id, event_version, decider, decider_id, data, command_id, previous_id, final)
    VALUES ('final_test_event', final_event_id, 1, 'final_test_decider', 'final-test-1', '{"final": true}', command_id_2, first_event_id, true);
    
    -- Verify stream is marked as final
    PERFORM test_assert_stream_final('final-test-1', 'final_test_decider', 'Stream should be marked as final');
    
    -- Now attempt to append another event (should fail due to trigger)
    PERFORM test_expect_error(
        format('SELECT append_event(''final_test_event'', ''%s'', ''final_test_decider'', ''final-test-1'', ''{"blocked": true}'', ''%s'', ''%s'', 1)', 
               blocked_event_id, command_id_3, final_event_id),
        'last event for this decider stream is already final',
        'Should prevent appending to finalized stream'
    );
END $$;

SELECT test_cleanup('test_final_event_trigger_prevents_append');

-- Test: check_final_event_for_decider trigger - should allow appending to non-finalized stream
SELECT test_setup('test_final_event_trigger_allows_non_final', 'unit');

-- Setup test data
SELECT register_decider_event('non_final_decider', 'non_final_event', 'Test non-final event', 1);

DO $$ 
DECLARE
    first_event_id UUID := gen_random_uuid();
    second_event_id UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
BEGIN
    -- Insert first event (not final)
    PERFORM append_event('non_final_event', first_event_id, 'non_final_decider', 'non-final-1', '{"event": 1}', command_id_1, null, 1);
    
    -- Should be able to append second event since stream is not final
    PERFORM append_event('non_final_event', second_event_id, 'non_final_decider', 'non-final-1', '{"event": 2}', command_id_2, first_event_id, 1);
    
    -- Verify both events exist
    PERFORM test_assert_event_count('non-final-1', 'non_final_decider', 2, 'Should have 2 events in non-final stream');
    
    -- Verify stream is not final
    PERFORM test_assert_stream_not_final('non-final-1', 'non_final_decider', 'Stream should not be marked as final');
END $$;

SELECT test_cleanup('test_final_event_trigger_allows_non_final');

-- Test: check_first_event_for_decider trigger - should allow null previous_id for first event
SELECT test_setup('test_first_event_trigger_allows_null_previous', 'unit');

-- Setup test data
SELECT register_decider_event('first_event_decider', 'first_event_test', 'Test first event validation', 1);

DO $$ 
DECLARE
    first_event_id UUID := gen_random_uuid();
    command_id UUID := gen_random_uuid();
BEGIN
    -- Should successfully insert first event with null previous_id
    PERFORM append_event('first_event_test', first_event_id, 'first_event_decider', 'first-event-1', '{"first": true}', command_id, null, 1);
    
    -- Verify event was inserted
    PERFORM test_assert_event_exists(first_event_id, 'first-event-1', 'first_event_decider', 'First event should be inserted successfully');
    
    -- Verify previous_id is null
    PERFORM test_assert_null(
        (SELECT previous_id FROM events WHERE event_id = first_event_id),
        'First event should have null previous_id'
    );
END $$;

SELECT test_cleanup('test_first_event_trigger_allows_null_previous');

-- Test: check_first_event_for_decider trigger - should prevent null previous_id for subsequent events
SELECT test_setup('test_first_event_trigger_prevents_null_subsequent', 'unit');

-- Setup test data
SELECT register_decider_event('subsequent_event_decider', 'subsequent_event_test', 'Test subsequent event validation', 1);

DO $$ 
DECLARE
    first_event_id UUID := gen_random_uuid();
    invalid_event_id UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
BEGIN
    -- Insert first event
    PERFORM append_event('subsequent_event_test', first_event_id, 'subsequent_event_decider', 'subsequent-1', '{"first": true}', command_id_1, null, 1);
    
    -- Attempt to insert second event with null previous_id (should fail)
    PERFORM test_expect_error(
        format('SELECT append_event(''subsequent_event_test'', ''%s'', ''subsequent_event_decider'', ''subsequent-1'', ''{"invalid": true}'', ''%s'', null, 1)', 
               invalid_event_id, command_id_2),
        'previous_id can only be null for the first decider event',
        'Should prevent null previous_id for subsequent events'
    );
END $$;

SELECT test_cleanup('test_first_event_trigger_prevents_null_subsequent');

-- Test: check_previous_id_in_same_decider trigger - should allow valid previous_id in same decider
SELECT test_setup('test_previous_id_trigger_allows_valid', 'unit');

-- Setup test data
SELECT register_decider_event('same_decider_test', 'same_decider_event', 'Test same decider validation', 1);

DO $$ 
DECLARE
    first_event_id UUID := gen_random_uuid();
    second_event_id UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
BEGIN
    -- Insert first event
    PERFORM append_event('same_decider_event', first_event_id, 'same_decider_test', 'same-decider-1', '{"event": 1}', command_id_1, null, 1);
    
    -- Insert second event with valid previous_id from same decider
    PERFORM append_event('same_decider_event', second_event_id, 'same_decider_test', 'same-decider-1', '{"event": 2}', command_id_2, first_event_id, 1);
    
    -- Verify both events exist and are properly linked
    PERFORM test_assert_event_count('same-decider-1', 'same_decider_test', 2, 'Should have 2 events in same decider');
    
    -- Verify previous_id chain is valid
    PERFORM test_assert_previous_id_chain_valid('same-decider-1', 'same_decider_test', 'Previous ID chain should be valid');
END $$;

SELECT test_cleanup('test_previous_id_trigger_allows_valid');

-- Test: check_previous_id_in_same_decider trigger - should prevent previous_id from different decider_id
SELECT test_setup('test_previous_id_trigger_prevents_different_decider_id', 'unit');

-- Setup test data
SELECT register_decider_event('cross_decider_test', 'cross_decider_event', 'Test cross decider validation', 1);

DO $$ 
DECLARE
    decider1_event_id UUID := gen_random_uuid();
    decider2_invalid_event_id UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
BEGIN
    -- Insert event in first decider_id
    PERFORM append_event('cross_decider_event', decider1_event_id, 'cross_decider_test', 'cross-decider-1', '{"decider": 1}', command_id_1, null, 1);
    
    -- Attempt to insert event in different decider_id with previous_id from first decider_id (should fail)
    PERFORM test_expect_error(
        format('SELECT append_event(''cross_decider_event'', ''%s'', ''cross_decider_test'', ''cross-decider-2'', ''{"invalid": true}'', ''%s'', ''%s'', 1)', 
               decider2_invalid_event_id, command_id_2, decider1_event_id),
        'previous_id must be in the same decider',
        'Should prevent previous_id from different decider_id'
    );
END $$;

SELECT test_cleanup('test_previous_id_trigger_prevents_different_decider_id');

-- Test: check_previous_id_in_same_decider trigger - should prevent previous_id from different decider type
SELECT test_setup('test_previous_id_trigger_prevents_different_decider_type', 'unit');

-- Setup test data for different decider types
SELECT register_decider_event('decider_type_1', 'type1_event', 'Test decider type 1', 1);
SELECT register_decider_event('decider_type_2', 'type2_event', 'Test decider type 2', 1);

DO $$ 
DECLARE
    type1_event_id UUID := gen_random_uuid();
    type2_invalid_event_id UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
BEGIN
    -- Insert event in first decider type
    PERFORM append_event('type1_event', type1_event_id, 'decider_type_1', 'same-id', '{"type": 1}', command_id_1, null, 1);
    
    -- Attempt to insert event in different decider type with previous_id from first type (should fail)
    PERFORM test_expect_error(
        format('SELECT append_event(''type2_event'', ''%s'', ''decider_type_2'', ''same-id'', ''{"invalid": true}'', ''%s'', ''%s'', 1)', 
               type2_invalid_event_id, command_id_2, type1_event_id),
        'previous_id must be in the same decider',
        'Should prevent previous_id from different decider type'
    );
END $$;

SELECT test_cleanup('test_previous_id_trigger_prevents_different_decider_type');

-- Test: check_previous_id_in_same_decider trigger - should prevent non-existent previous_id
SELECT test_setup('test_previous_id_trigger_prevents_nonexistent', 'unit');

-- Setup test data
SELECT register_decider_event('nonexistent_test', 'nonexistent_event', 'Test nonexistent previous_id', 1);

DO $$ 
DECLARE
    nonexistent_previous_id UUID := gen_random_uuid();
    invalid_event_id UUID := gen_random_uuid();
    command_id UUID := gen_random_uuid();
BEGIN
    -- Attempt to insert event with non-existent previous_id (should fail)
    PERFORM test_expect_error(
        format('SELECT append_event(''nonexistent_event'', ''%s'', ''nonexistent_test'', ''nonexistent-1'', ''{"invalid": true}'', ''%s'', ''%s'', 1)', 
               invalid_event_id, command_id, nonexistent_previous_id),
        'previous_id must be in the same decider',
        'Should prevent non-existent previous_id'
    );
END $$;

SELECT test_cleanup('test_previous_id_trigger_prevents_nonexistent');

-- Test: Complex trigger interaction - multiple triggers working together
SELECT test_setup('test_triggers_complex_interaction', 'unit');

-- Setup test data
SELECT register_decider_event('complex_decider', 'complex_event', 'Test complex trigger interaction', 1);

DO $$ 
DECLARE
    event1_id UUID := gen_random_uuid();
    event2_id UUID := gen_random_uuid();
    final_event_id UUID := gen_random_uuid();
    blocked_event_id UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
    command_id_3 UUID := gen_random_uuid();
    command_id_4 UUID := gen_random_uuid();
BEGIN
    -- Insert first event (triggers: first_event allows null previous_id, previous_id validation passes)
    PERFORM append_event('complex_event', event1_id, 'complex_decider', 'complex-1', '{"event": 1}', command_id_1, null, 1);
    
    -- Insert second event (triggers: first_event prevents null previous_id, previous_id validation passes, final_event allows append)
    PERFORM append_event('complex_event', event2_id, 'complex_decider', 'complex-1', '{"event": 2}', command_id_2, event1_id, 1);
    
    -- Insert final event
    INSERT INTO events (event, event_id, event_version, decider, decider_id, data, command_id, previous_id, final)
    VALUES ('complex_event', final_event_id, 1, 'complex_decider', 'complex-1', '{"final": true}', command_id_3, event2_id, true);
    
    -- Verify all valid events were inserted
    PERFORM test_assert_event_count('complex-1', 'complex_decider', 3, 'Should have 3 events after valid operations');
    
    -- Verify stream is final
    PERFORM test_assert_stream_final('complex-1', 'complex_decider', 'Stream should be final after final event');
    
    -- Attempt to append to finalized stream (should fail due to final_event trigger)
    PERFORM test_expect_error(
        format('SELECT append_event(''complex_event'', ''%s'', ''complex_decider'', ''complex-1'', ''{"blocked": true}'', ''%s'', ''%s'', 1)', 
               blocked_event_id, command_id_4, final_event_id),
        'last event for this decider stream is already final',
        'Should prevent appending to finalized stream in complex scenario'
    );
    
    -- Verify previous_id chain is still valid
    PERFORM test_assert_previous_id_chain_valid('complex-1', 'complex_decider', 'Previous ID chain should remain valid in complex scenario');
END $$;

SELECT test_cleanup('test_triggers_complex_interaction');
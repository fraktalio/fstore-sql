-- ##########################################################################################
-- ##########################################################################################
-- ######                    FOREIGN KEY AND UNIQUENESS CONSTRAINTS TESTS         ######
-- ##########################################################################################
-- ##########################################################################################

-- Test: Foreign key constraint - should allow valid decider-event combination
SELECT test_setup('test_foreign_key_allows_valid_combination', 'unit');

-- Setup test data
SELECT register_decider_event('fk_test_decider', 'fk_test_event', 'Test foreign key validation', 1);

DO $$ 
DECLARE
    test_event_id UUID := gen_random_uuid();
    command_id UUID := gen_random_uuid();
BEGIN
    -- Should successfully insert event with registered decider-event combination
    PERFORM append_event('fk_test_event', test_event_id, 'fk_test_decider', 'fk-test-1', '{"valid": true}', command_id, null, 1);
    
    -- Verify event was inserted
    PERFORM test_assert_event_exists(test_event_id, 'fk-test-1', 'fk_test_decider', 'Event with valid foreign key should be inserted');
END $$;

SELECT test_cleanup('test_foreign_key_allows_valid_combination');

-- Test: Foreign key constraint - should prevent unregistered decider-event combination
SELECT test_setup('test_foreign_key_prevents_unregistered_combination', 'unit');

DO $$ 
DECLARE
    invalid_event_id UUID := gen_random_uuid();
    command_id UUID := gen_random_uuid();
BEGIN
    -- Attempt to insert event with unregistered decider-event combination (should fail)
    PERFORM test_expect_error(
        format('SELECT append_event(''unregistered_event'', ''%s'', ''unregistered_decider'', ''invalid-1'', ''{"invalid": true}'', ''%s'', null, 1)', 
               invalid_event_id, command_id),
        'violates foreign key constraint',
        'Should prevent unregistered decider-event combination'
    );
END $$;

SELECT test_cleanup('test_foreign_key_prevents_unregistered_combination');

-- Test: Foreign key constraint - should prevent wrong event version
-- Test: Foreign key constraint - should prevent wrong event version
SELECT test_setup('test_foreign_key_prevents_wrong_version', 'unit');

-- Setup test data with specific version
SELECT register_decider_event('version_test_decider', 'version_test_event', 'Test version validation', 2);

DO $$ 
DECLARE
    invalid_event_id UUID := gen_random_uuid();
    command_id UUID := gen_random_uuid();
BEGIN
    -- Attempt to insert event with wrong version (should fail)
    PERFORM test_expect_error(
        format('SELECT append_event(''version_test_event'', ''%s'', ''version_test_decider'', ''version-test-1'', ''{"invalid": true}'', ''%s'', null, 1)', 
               invalid_event_id, command_id),
        'violates foreign key constraint',
        'Should prevent wrong event version'
    );
END $$;

SELECT test_cleanup('test_foreign_key_prevents_wrong_version');

-- Test: Foreign key constraint - should allow correct event version
SELECT test_setup('test_foreign_key_allows_correct_version', 'unit');

DO $$ 
DECLARE
    valid_event_id UUID := gen_random_uuid();
    command_id UUID := gen_random_uuid();
BEGIN
    -- Should successfully insert event with correct version
    PERFORM append_event('version_test_event', valid_event_id, 'version_test_decider', 'version-test-2', '{"valid": true}', command_id, null, 2);
    
    -- Verify event was inserted
    PERFORM test_assert_event_exists(valid_event_id, 'version-test-2', 'version_test_decider', 'Event with correct version should be inserted');
END $$;

SELECT test_cleanup('test_foreign_key_allows_correct_version');

-- Test: Event ID uniqueness constraint - should allow unique event IDs
SELECT test_setup('test_event_id_uniqueness_allows_unique', 'unit');

-- Setup test data
SELECT register_decider_event('unique_test_decider', 'unique_test_event', 'Test uniqueness validation', 1);

DO $$ 
DECLARE
    event_id_1 UUID := gen_random_uuid();
    event_id_2 UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
BEGIN
    -- Insert first event
    PERFORM append_event('unique_test_event', event_id_1, 'unique_test_decider', 'unique-test-1', '{"event": 1}', command_id_1, null, 1);
    
    -- Insert second event with different event_id (should succeed)
    PERFORM append_event('unique_test_event', event_id_2, 'unique_test_decider', 'unique-test-2', '{"event": 2}', command_id_2, null, 1);
    
    -- Verify both events exist
    PERFORM test_assert_event_exists(event_id_1, 'unique-test-1', 'unique_test_decider', 'First unique event should exist');
    PERFORM test_assert_event_exists(event_id_2, 'unique-test-2', 'unique_test_decider', 'Second unique event should exist');
END $$;

SELECT test_cleanup('test_event_id_uniqueness_allows_unique');

-- Test: Event ID uniqueness constraint - should prevent duplicate event IDs
SELECT test_setup('test_event_id_uniqueness_prevents_duplicate', 'unit');

DO $$ 
DECLARE
    duplicate_event_id UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
BEGIN
    -- Insert first event
    PERFORM append_event('unique_test_event', duplicate_event_id, 'unique_test_decider', 'duplicate-test-1', '{"event": 1}', command_id_1, null, 1);
    
    -- Attempt to insert second event with same event_id (should fail)
    PERFORM test_expect_error(
        format('SELECT append_event(''unique_test_event'', ''%s'', ''unique_test_decider'', ''duplicate-test-2'', ''{"event": 2}'', ''%s'', null, 1)', 
               duplicate_event_id, command_id_2),
        'duplicate key value violates unique constraint',
        'Should prevent duplicate event IDs'
    );
END $$;

SELECT test_cleanup('test_event_id_uniqueness_prevents_duplicate');

-- Test: Previous ID uniqueness constraint - should allow multiple null previous_id values
SELECT test_setup('test_previous_id_uniqueness_allows_multiple_nulls', 'unit');

-- Setup test data
SELECT register_decider_event('null_previous_decider', 'null_previous_event', 'Test null previous_id uniqueness', 1);

DO $$ 
DECLARE
    event_id_1 UUID := gen_random_uuid();
    event_id_2 UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
BEGIN
    -- Insert first event with null previous_id
    PERFORM append_event('null_previous_event', event_id_1, 'null_previous_decider', 'null-test-1', '{"event": 1}', command_id_1, null, 1);
    
    -- Insert second event with null previous_id in different decider_id (should succeed due to null handling)
    PERFORM append_event('null_previous_event', event_id_2, 'null_previous_decider', 'null-test-2', '{"event": 2}', command_id_2, null, 1);
    
    -- Verify both events exist (this tests that null values don't trigger unique constraint)
    PERFORM test_assert_event_exists(event_id_1, 'null-test-1', 'null_previous_decider', 'First event with null previous_id should exist');
    PERFORM test_assert_event_exists(event_id_2, 'null-test-2', 'null_previous_decider', 'Second event with null previous_id should exist');
END $$;

SELECT test_cleanup('test_previous_id_uniqueness_allows_multiple_nulls');

-- Test: Previous ID uniqueness constraint - should prevent duplicate non-null previous_id values
SELECT test_setup('test_previous_id_uniqueness_prevents_duplicate_non_null', 'unit');

-- Setup test data
SELECT register_decider_event('duplicate_previous_decider', 'duplicate_previous_event', 'Test duplicate previous_id', 1);

DO $$ 
DECLARE
    first_event_id UUID := gen_random_uuid();
    second_event_id UUID := gen_random_uuid();
    third_event_id UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
    command_id_3 UUID := gen_random_uuid();
BEGIN
    -- Insert first event
    PERFORM append_event('duplicate_previous_event', first_event_id, 'duplicate_previous_decider', 'dup-prev-1', '{"event": 1}', command_id_1, null, 1);
    
    -- Insert second event with first_event_id as previous_id
    PERFORM append_event('duplicate_previous_event', second_event_id, 'duplicate_previous_decider', 'dup-prev-1', '{"event": 2}', command_id_2, first_event_id, 1);
    
    -- Attempt to insert third event with same previous_id in different decider_id (should fail due to trigger first)
    PERFORM test_expect_error(
        format('SELECT append_event(''duplicate_previous_event'', ''%s'', ''duplicate_previous_decider'', ''dup-prev-2'', ''{"event": 3}'', ''%s'', ''%s'', 1)', 
               third_event_id, command_id_3, first_event_id),
        'previous_id must be in the same decider',
        'Should prevent using previous_id from different decider_id'
    );
    
    -- Now test actual uniqueness constraint by trying to insert with same previous_id in same decider_id
    PERFORM test_expect_error(
        format('INSERT INTO events (event, event_id, event_version, decider, decider_id, data, command_id, previous_id) VALUES (''duplicate_previous_event'', ''%s'', 1, ''duplicate_previous_decider'', ''dup-prev-1'', ''{"duplicate": true}'', ''%s'', ''%s'')', 
               gen_random_uuid(), gen_random_uuid(), first_event_id),
        'duplicate key value violates unique constraint',
        'Should prevent duplicate non-null previous_id values'
    );
END $$;

SELECT test_cleanup('test_previous_id_uniqueness_prevents_duplicate_non_null');

-- Test: Complex constraint interaction - foreign key and uniqueness working together
SELECT test_setup('test_complex_constraint_interaction', 'unit');

-- Setup test data with multiple versions
SELECT register_decider_event('complex_constraint_decider', 'complex_constraint_event', 'Test complex constraints v1', 1);
SELECT register_decider_event('complex_constraint_decider', 'complex_constraint_event', 'Test complex constraints v2', 2);

DO $$ 
DECLARE
    event_id_1 UUID := gen_random_uuid();
    event_id_2 UUID := gen_random_uuid();
    event_id_3 UUID := gen_random_uuid();
    duplicate_event_id UUID;
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
    command_id_3 UUID := gen_random_uuid();
BEGIN
    -- Insert event with version 1
    PERFORM append_event('complex_constraint_event', event_id_1, 'complex_constraint_decider', 'complex-1', '{"version": 1}', command_id_1, null, 1);
    
    -- Insert event with version 2 (different version, should work)
    PERFORM append_event('complex_constraint_event', event_id_2, 'complex_constraint_decider', 'complex-2', '{"version": 2}', command_id_2, null, 2);
    
    -- Insert chained event with version 1
    PERFORM append_event('complex_constraint_event', event_id_3, 'complex_constraint_decider', 'complex-1', '{"chained": true}', command_id_3, event_id_1, 1);
    
    -- Verify all valid events were inserted
    PERFORM test_assert_event_exists(event_id_1, 'complex-1', 'complex_constraint_decider', 'Version 1 event should exist');
    PERFORM test_assert_event_exists(event_id_2, 'complex-2', 'complex_constraint_decider', 'Version 2 event should exist');
    PERFORM test_assert_event_exists(event_id_3, 'complex-1', 'complex_constraint_decider', 'Chained event should exist');
    
    -- Store event_id_1 for duplicate test
    duplicate_event_id := event_id_1;
    
    -- Test that duplicate event_id fails (uniqueness constraint)
    PERFORM test_expect_error(
        format('INSERT INTO events (event, event_id, event_version, decider, decider_id, data, command_id, previous_id) VALUES (''complex_constraint_event'', ''%s'', 1, ''complex_constraint_decider'', ''duplicate-test'', ''{"duplicate": true}'', ''%s'', null)', 
               duplicate_event_id, gen_random_uuid()),
        'duplicate key value violates unique constraint',
        'Should prevent duplicate event_id in complex scenario'
    );
    
    -- Test that unregistered version fails (foreign key constraint)
    PERFORM test_expect_error(
        format('SELECT append_event(''complex_constraint_event'', ''%s'', ''complex_constraint_decider'', ''invalid-version'', ''{"invalid": true}'', ''%s'', null, 99)', 
               gen_random_uuid(), gen_random_uuid()),
        'violates foreign key constraint',
        'Should prevent unregistered version in complex scenario'
    );
END $$;

SELECT test_cleanup('test_complex_constraint_interaction');

-- Test: Constraint behavior during transaction rollback
SELECT test_setup('test_constraints_transaction_rollback', 'unit');

-- Setup test data
SELECT register_decider_event('rollback_constraint_decider', 'rollback_constraint_event', 'Test rollback constraints', 1);

DO $$
DECLARE
    event_id_1 UUID := gen_random_uuid();
    event_id_2 UUID := gen_random_uuid();
    command_id_1 UUID := gen_random_uuid();
    command_id_2 UUID := gen_random_uuid();
    initial_count INTEGER;
    final_count INTEGER;
BEGIN
    -- Get initial event count
    SELECT COUNT(*) INTO initial_count FROM events WHERE decider = 'rollback_constraint_decider';
    
    -- Start transaction that will be rolled back
    BEGIN
        -- Insert valid event
        PERFORM append_event('rollback_constraint_event', event_id_1, 'rollback_constraint_decider', 'rollback-1', '{"valid": true}', command_id_1, null, 1);
        
        -- Attempt to insert duplicate event_id (should fail and rollback transaction)
        PERFORM append_event('rollback_constraint_event', event_id_1, 'rollback_constraint_decider', 'rollback-2', '{"duplicate": true}', command_id_2, null, 1);
        
    EXCEPTION
        WHEN OTHERS THEN
            -- Expected rollback due to constraint violation
            NULL;
    END;
    
    -- Get final event count
    SELECT COUNT(*) INTO final_count FROM events WHERE decider = 'rollback_constraint_decider';
    
    -- Verify that transaction was properly rolled back
    PERFORM test_assert_equals(
        initial_count,
        final_count,
        'Transaction should be rolled back on constraint violation'
    );
    
    -- Verify that no events were inserted
    PERFORM test_assert_event_not_exists(event_id_1, 'Event should not exist after rollback');
END $$;

SELECT test_cleanup('test_constraints_transaction_rollback');
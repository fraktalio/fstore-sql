-- ##########################################################################################
-- ######                    REGISTER_DECIDER_EVENT FUNCTION TESTS                ######
-- ##########################################################################################

-- Simple test for register_decider_event function
\echo 'Testing register_decider_event function...'

-- Clean up any existing test data
DELETE FROM events WHERE decider_id LIKE 'test_%';
DELETE FROM deciders WHERE decider LIKE 'test_%';

-- Test 1: Basic decider event registration
\echo 'Test 1: Basic decider event registration'

DO $$
DECLARE
    result_record deciders;
    registration_count INTEGER;
BEGIN
    -- Register a decider event
    SELECT * INTO result_record FROM register_decider_event('register_test_decider', 'register_test_event', 'Test event description', 1);
    
    -- Verify the result
    IF result_record.decider != 'register_test_decider' THEN
        RAISE EXCEPTION 'Test failed: decider name mismatch';
    END IF;
    
    IF result_record.event != 'register_test_event' THEN
        RAISE EXCEPTION 'Test failed: event name mismatch';
    END IF;
    
    IF result_record.event_version != 1 THEN
        RAISE EXCEPTION 'Test failed: event version mismatch';
    END IF;
    
    -- Verify it exists in the database
    SELECT COUNT(*) INTO registration_count FROM deciders 
    WHERE decider = 'register_test_decider' AND event = 'register_test_event' AND event_version = 1;
    
    IF registration_count != 1 THEN
        RAISE EXCEPTION 'Test failed: Registration not found in database';
    END IF;
    
    RAISE NOTICE 'Test 1 PASSED: Basic registration works';
END;
$$;

-- Test 2: Multiple event versions
\echo 'Test 2: Multiple event versions'

DO $$
DECLARE
    result1 deciders;
    result2 deciders;
    total_count INTEGER;
BEGIN
    -- Register different versions of the same event
    SELECT * INTO result1 FROM register_decider_event('version_decider', 'version_event', 'Version 1', 1);
    SELECT * INTO result2 FROM register_decider_event('version_decider', 'version_event', 'Version 2', 2);
    
    -- Verify both versions exist
    SELECT COUNT(*) INTO total_count FROM deciders 
    WHERE decider = 'version_decider' AND event = 'version_event';
    
    IF total_count != 2 THEN
        RAISE EXCEPTION 'Test failed: Expected 2 versions, got %', total_count;
    END IF;
    
    RAISE NOTICE 'Test 2 PASSED: Multiple versions work';
END;
$$;

-- Test 3: Duplicate registration (should fail with constraint error)
\echo 'Test 3: Duplicate registration'

DO $$
DECLARE
    result1 deciders;
    error_occurred BOOLEAN := FALSE;
BEGIN
    -- Register the same decider event twice
    SELECT * INTO result1 FROM register_decider_event('dup_decider', 'dup_event', 'First registration', 1);
    
    -- Try to register the same combination again (should fail)
    BEGIN
        PERFORM register_decider_event('dup_decider', 'dup_event', 'Second registration', 1);
    EXCEPTION WHEN OTHERS THEN
        error_occurred := TRUE;
    END;
    
    IF NOT error_occurred THEN
        RAISE EXCEPTION 'Test failed: Duplicate registration should have failed';
    END IF;
    
    RAISE NOTICE 'Test 3 PASSED: Duplicate registration correctly fails';
END;
$$;

\echo 'register_decider_event tests completed successfully';
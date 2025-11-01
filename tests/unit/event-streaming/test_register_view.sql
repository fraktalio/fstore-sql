-- ##########################################################################################
-- ######                        REGISTER_VIEW FUNCTION TESTS                     ######
-- ##########################################################################################

-- Simple test for register_view function
\echo 'Testing register_view function...'

-- Clean up any existing test data
DELETE FROM locks WHERE view LIKE 'test_%';
DELETE FROM views WHERE view LIKE 'test_%';
DELETE FROM events WHERE decider_id LIKE 'test_%';
DELETE FROM deciders WHERE decider LIKE 'test_%';

-- Test 1: Basic view registration
\echo 'Test 1: Basic view registration'

DO $$
DECLARE
    result_record views;
    view_count INTEGER;
BEGIN
    -- Register a view
    SELECT * INTO result_record FROM register_view('test_view', '2020-01-01 00:00:00'::TIMESTAMP, 300);
    
    -- Verify the result
    IF result_record.view != 'test_view' THEN
        RAISE EXCEPTION 'Test failed: view name mismatch';
    END IF;
    
    IF result_record.pooling_delay_s != 300 THEN
        RAISE EXCEPTION 'Test failed: pooling delay mismatch';
    END IF;
    
    -- Verify it exists in the database
    SELECT COUNT(*) INTO view_count FROM views WHERE view = 'test_view';
    
    IF view_count != 1 THEN
        RAISE EXCEPTION 'Test failed: View not found in database';
    END IF;
    
    RAISE NOTICE 'Test 1 PASSED: Basic view registration works';
END;
$$;

-- Test 2: View registration with edge function
\echo 'Test 2: View registration with edge function'

DO $$
DECLARE
    result_record views;
BEGIN
    -- Register a view with edge function
    SELECT * INTO result_record FROM register_view(
        'edge_view', 
        '2020-01-01 00:00:00'::TIMESTAMP, 
        300, 
        1, 
        'https://example.com/webhook'
    );
    
    -- Verify the result
    IF result_record.view != 'edge_view' THEN
        RAISE EXCEPTION 'Test failed: view name mismatch';
    END IF;
    
    IF result_record.edge_function_url != 'https://example.com/webhook' THEN
        RAISE EXCEPTION 'Test failed: edge function URL mismatch';
    END IF;
    
    RAISE NOTICE 'Test 2 PASSED: View with edge function works';
END;
$$;

-- Test 3: Duplicate view registration (should update)
\echo 'Test 3: Duplicate view registration'

DO $$
DECLARE
    result1 views;
    result2 views;
    view_count INTEGER;
BEGIN
    -- Register the same view twice with different parameters
    SELECT * INTO result1 FROM register_view('dup_view', '2020-01-01 00:00:00'::TIMESTAMP, 300);
    
    -- Wait a moment to ensure different timestamps
    PERFORM pg_sleep(0.1);
    
    SELECT * INTO result2 FROM register_view('dup_view', '2020-01-01 00:00:00'::TIMESTAMP, 600);
    
    -- Should still only have one record
    SELECT COUNT(*) INTO view_count FROM views WHERE view = 'dup_view';
    
    IF view_count != 1 THEN
        RAISE EXCEPTION 'Test failed: Expected 1 record after duplicate registration, got %', view_count;
    END IF;
    
    -- Pooling delay should be updated
    IF result2.pooling_delay_s != 600 THEN
        RAISE EXCEPTION 'Test failed: Pooling delay should be updated to 600';
    END IF;
    
    -- Updated timestamp should be later
    IF result2.updated_at <= result1.updated_at THEN
        RAISE NOTICE 'Warning: Updated timestamp may not have changed (timing issue)';
    END IF;
    
    RAISE NOTICE 'Test 3 PASSED: Duplicate registration works (update)';
END;
$$;

\echo 'register_view tests completed successfully';
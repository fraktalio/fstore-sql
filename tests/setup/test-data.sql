-- ##########################################################################################
-- ##########################################################################################
-- ######                            COMMON TEST DATA PATTERNS                     ######
-- ##########################################################################################
-- ##########################################################################################

-- This script provides common test data patterns and helper functions
-- for setting up consistent test scenarios across different test suites

\echo 'Loading common test data patterns...'

-- ##########################################################################################
-- ######                              TEST DATA CONSTANTS                         ######
-- ##########################################################################################

-- Standard test decider types
DO $$
BEGIN
    -- Register standard test deciders and events
    PERFORM register_decider_event('test_decider', 'test_event_created', 'Test event for basic scenarios', 1);
    PERFORM register_decider_event('test_decider', 'test_event_updated', 'Test event for update scenarios', 1);
    PERFORM register_decider_event('test_decider', 'test_event_deleted', 'Test event for deletion scenarios', 1);
    PERFORM register_decider_event('test_decider', 'test_event_final', 'Test event for stream finalization', 1);
    
    -- Register concurrent test deciders
    PERFORM register_decider_event('concurrent_decider', 'concurrent_event', 'Test event for concurrency scenarios', 1);
    
    -- Register performance test deciders
    PERFORM register_decider_event('perf_decider', 'perf_event', 'Test event for performance scenarios', 1);
    
    -- Register constraint test deciders
    PERFORM register_decider_event('constraint_decider', 'constraint_event', 'Test event for constraint validation', 1);
    
    RAISE NOTICE 'Standard test deciders and events registered';
END $$;

-- ##########################################################################################
-- ######                              TEST DATA HELPERS                           ######
-- ##########################################################################################

-- API: Generate a test UUID with a predictable pattern for easier debugging
CREATE OR REPLACE FUNCTION test_generate_uuid(prefix TEXT DEFAULT 'test')
    RETURNS UUID AS
$$
BEGIN
    -- Generate UUID with timestamp component for uniqueness and debugging
    RETURN (prefix || '-' || EXTRACT(EPOCH FROM NOW())::TEXT || '-' || EXTRACT(MICROSECONDS FROM NOW())::TEXT)::UUID;
EXCEPTION WHEN OTHERS THEN
    -- Fallback to random UUID if the formatted one fails
    RETURN gen_random_uuid();
END;
$$ LANGUAGE plpgsql;

-- API: Create a basic test event sequence for a decider
CREATE OR REPLACE FUNCTION test_create_event_sequence(
    p_decider_id TEXT,
    p_event_count INTEGER DEFAULT 3,
    p_decider TEXT DEFAULT 'test_decider',
    p_event TEXT DEFAULT 'test_event_created'
)
    RETURNS TABLE(event_id UUID, "offset" BIGINT) AS
$$
DECLARE
    i INTEGER;
    current_event_id UUID;
    previous_event_id UUID := NULL;
    result_event_id UUID;
    result_offset BIGINT;
BEGIN
    FOR i IN 1..p_event_count LOOP
        current_event_id := test_generate_uuid('seq');
        
        INSERT INTO events (event, event_id, decider, decider_id, data, command_id, previous_id)
        VALUES (
            p_event,
            current_event_id,
            p_decider,
            p_decider_id,
            format('{"sequence": %s, "timestamp": "%s"}', i, NOW())::JSONB,
            test_generate_uuid('cmd'),
            previous_event_id
        )
        RETURNING events.event_id, events."offset" INTO result_event_id, result_offset;
        
        previous_event_id := current_event_id;
        
        event_id := result_event_id;
        "offset" := result_offset;
        RETURN NEXT;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- API: Create test data for concurrent access scenarios
CREATE OR REPLACE FUNCTION test_create_concurrent_data(
    p_decider_count INTEGER DEFAULT 3,
    p_events_per_decider INTEGER DEFAULT 2
)
    RETURNS VOID AS
$$
DECLARE
    i INTEGER;
    decider_id TEXT;
BEGIN
    FOR i IN 1..p_decider_count LOOP
        decider_id := 'concurrent_decider_' || i;
        PERFORM test_create_event_sequence(decider_id, p_events_per_decider, 'concurrent_decider', 'concurrent_event');
    END LOOP;
    
    RAISE NOTICE 'Created concurrent test data: % deciders with % events each', p_decider_count, p_events_per_decider;
END;
$$ LANGUAGE plpgsql;

-- API: Create test views for streaming scenarios
CREATE OR REPLACE FUNCTION test_create_standard_views()
    RETURNS VOID AS
$$
BEGIN
    -- Basic test view
    PERFORM register_view('test_view_basic', NOW() - INTERVAL '1 hour', 300, NULL, NULL);
    
    -- Concurrent test view
    PERFORM register_view('test_view_concurrent', NOW() - INTERVAL '1 hour', 300, NULL, NULL);
    
    -- Performance test view
    PERFORM register_view('test_view_performance', NOW() - INTERVAL '1 hour', 600, NULL, NULL);
    
    -- Short timeout view for timeout testing
    PERFORM register_view('test_view_short_timeout', NOW() - INTERVAL '1 hour', 5, NULL, NULL);
    
    RAISE NOTICE 'Standard test views created';
END;
$$ LANGUAGE plpgsql;

-- API: Clean up all test data (events, views, locks, but preserve decider registrations)
CREATE OR REPLACE FUNCTION test_cleanup_data()
    RETURNS VOID AS
$$
BEGIN
    -- Clean up in dependency order
    DELETE FROM locks WHERE view LIKE 'test_%';
    DELETE FROM views WHERE view LIKE 'test_%';
    DELETE FROM events WHERE decider_id LIKE 'test_%' OR decider_id LIKE 'concurrent_%' OR decider_id LIKE 'perf_%' OR decider_id LIKE 'constraint_%';
    
    -- Clear test results
    PERFORM test_clear_results();
    
    RAISE NOTICE 'Test data cleanup complete';
END;
$$ LANGUAGE plpgsql;

-- API: Reset database to clean state (full reset including decider registrations)
CREATE OR REPLACE FUNCTION test_reset_database()
    RETURNS VOID AS
$$
BEGIN
    -- Clean up all data
    DELETE FROM locks;
    DELETE FROM views;
    DELETE FROM events;
    DELETE FROM deciders;
    
    -- Clear test results
    PERFORM test_clear_results();
    
    -- Re-register standard test deciders
    PERFORM register_decider_event('test_decider', 'test_event_created', 'Test event for basic scenarios', 1);
    PERFORM register_decider_event('test_decider', 'test_event_updated', 'Test event for update scenarios', 1);
    PERFORM register_decider_event('test_decider', 'test_event_deleted', 'Test event for deletion scenarios', 1);
    PERFORM register_decider_event('test_decider', 'test_event_final', 'Test event for stream finalization', 1);
    PERFORM register_decider_event('concurrent_decider', 'concurrent_event', 'Test event for concurrency scenarios', 1);
    PERFORM register_decider_event('perf_decider', 'perf_event', 'Test event for performance scenarios', 1);
    PERFORM register_decider_event('constraint_decider', 'constraint_event', 'Test event for constraint validation', 1);
    
    RAISE NOTICE 'Database reset to clean state complete';
END;
$$ LANGUAGE plpgsql;

-- ##########################################################################################
-- ######                              SAMPLE TEST DATA                            ######
-- ##########################################################################################

-- API: Create sample test data for development and debugging
CREATE OR REPLACE FUNCTION test_create_sample_data()
    RETURNS VOID AS
$$
DECLARE
    sample_event_id UUID;
    sample_command_id UUID;
BEGIN
    -- Create some sample events for manual testing
    sample_event_id := test_generate_uuid('sample');
    sample_command_id := test_generate_uuid('cmd');
    
    PERFORM append_event(
        'test_event_created',
        sample_event_id,
        'test_decider',
        'sample_decider_1',
        '{"name": "Sample Entity", "status": "created"}'::JSONB,
        sample_command_id,
        NULL
    );
    
    -- Create a second event in the same stream
    sample_event_id := test_generate_uuid('sample');
    sample_command_id := test_generate_uuid('cmd');
    
    PERFORM append_event(
        'test_event_updated',
        sample_event_id,
        'test_decider',
        'sample_decider_1',
        '{"name": "Sample Entity Updated", "status": "updated"}'::JSONB,
        sample_command_id,
        (SELECT event_id FROM events WHERE decider_id = 'sample_decider_1' ORDER BY "offset" DESC LIMIT 1)
    );
    
    -- Create sample views
    PERFORM test_create_standard_views();
    
    RAISE NOTICE 'Sample test data created';
END;
$$ LANGUAGE plpgsql;

\echo 'Common test data patterns loaded!'
\echo 'Available test data functions:'
\echo '  - test_generate_uuid(prefix): Generate predictable test UUIDs'
\echo '  - test_create_event_sequence(decider_id, count): Create event sequence'
\echo '  - test_create_concurrent_data(decider_count, events_per_decider): Create concurrent test data'
\echo '  - test_create_standard_views(): Create standard test views'
\echo '  - test_cleanup_data(): Clean up test data (preserve registrations)'
\echo '  - test_reset_database(): Full database reset'
\echo '  - test_create_sample_data(): Create sample data for development'
\echo ''
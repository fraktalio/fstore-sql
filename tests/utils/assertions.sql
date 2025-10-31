-- ##########################################################################################
-- ##########################################################################################
-- ######                     EVENT STORE SPECIALIZED ASSERTIONS                   ######
-- ##########################################################################################
-- ##########################################################################################

-- API: Assert that an event exists with specific properties
CREATE OR REPLACE FUNCTION test_assert_event_exists(
    p_event_id UUID,
    p_decider_id TEXT,
    p_decider TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    event_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO event_count
    FROM events
    WHERE event_id = p_event_id
      AND decider_id = p_decider_id
      AND decider = p_decider;
    
    RETURN test_assert(
        event_count = 1,
        format('%s - Event should exist: event_id=%s, decider_id=%s, decider=%s', 
               message, p_event_id, p_decider_id, p_decider)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that an event does not exist
CREATE OR REPLACE FUNCTION test_assert_event_not_exists(
    p_event_id UUID,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    event_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO event_count
    FROM events
    WHERE event_id = p_event_id;
    
    RETURN test_assert(
        event_count = 0,
        format('%s - Event should not exist: event_id=%s', message, p_event_id)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert event count for a specific decider
CREATE OR REPLACE FUNCTION test_assert_event_count(
    p_decider_id TEXT,
    p_decider TEXT,
    expected_count INTEGER,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    actual_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO actual_count
    FROM events
    WHERE decider_id = p_decider_id
      AND decider = p_decider;
    
    RETURN test_assert_equals(
        expected_count,
        actual_count,
        format('%s - Event count for decider_id=%s, decider=%s', 
               message, p_decider_id, p_decider)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that events are properly ordered within a decider stream
CREATE OR REPLACE FUNCTION test_assert_event_ordering(
    p_decider_id TEXT,
    p_decider TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    ordering_violations INTEGER;
BEGIN
    -- Check if events are properly ordered by offset within the decider stream
    SELECT COUNT(*) INTO ordering_violations
    FROM (
        SELECT 
            event_id,
            "offset",
            LAG("offset") OVER (ORDER BY "offset") as prev_offset
        FROM events
        WHERE decider_id = p_decider_id
          AND decider = p_decider
        ORDER BY "offset"
    ) ordered_events
    WHERE prev_offset IS NOT NULL AND "offset" <= prev_offset;
    
    RETURN test_assert(
        ordering_violations = 0,
        format('%s - Events should be properly ordered for decider_id=%s, decider=%s', 
               message, p_decider_id, p_decider)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that a decider event registration exists
CREATE OR REPLACE FUNCTION test_assert_decider_event_registered(
    p_decider TEXT,
    p_event TEXT,
    p_event_version BIGINT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    registration_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO registration_count
    FROM deciders
    WHERE decider = p_decider
      AND event = p_event
      AND event_version = p_event_version;
    
    RETURN test_assert(
        registration_count = 1,
        format('%s - Decider event should be registered: decider=%s, event=%s, version=%s', 
               message, p_decider, p_event, p_event_version)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that a view is registered
CREATE OR REPLACE FUNCTION test_assert_view_registered(
    p_view TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    view_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO view_count
    FROM views
    WHERE view = p_view;
    
    RETURN test_assert(
        view_count = 1,
        format('%s - View should be registered: view=%s', message, p_view)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that a lock exists for a view and decider
CREATE OR REPLACE FUNCTION test_assert_lock_exists(
    p_view TEXT,
    p_decider_id TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    lock_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO lock_count
    FROM locks
    WHERE view = p_view
      AND decider_id = p_decider_id;
    
    RETURN test_assert(
        lock_count = 1,
        format('%s - Lock should exist: view=%s, decider_id=%s', 
               message, p_view, p_decider_id)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that a lock is currently active (locked)
CREATE OR REPLACE FUNCTION test_assert_lock_active(
    p_view TEXT,
    p_decider_id TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    is_locked BOOLEAN;
BEGIN
    SELECT locked_until > NOW() INTO is_locked
    FROM locks
    WHERE view = p_view
      AND decider_id = p_decider_id;
    
    RETURN test_assert(
        COALESCE(is_locked, FALSE),
        format('%s - Lock should be active: view=%s, decider_id=%s', 
               message, p_view, p_decider_id)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that a lock is not active (unlocked)
CREATE OR REPLACE FUNCTION test_assert_lock_inactive(
    p_view TEXT,
    p_decider_id TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    is_locked BOOLEAN;
BEGIN
    SELECT locked_until > NOW() INTO is_locked
    FROM locks
    WHERE view = p_view
      AND decider_id = p_decider_id;
    
    RETURN test_assert(
        NOT COALESCE(is_locked, FALSE),
        format('%s - Lock should be inactive: view=%s, decider_id=%s', 
               message, p_view, p_decider_id)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that an event stream is final
CREATE OR REPLACE FUNCTION test_assert_stream_final(
    p_decider_id TEXT,
    p_decider TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    has_final_event BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM events
        WHERE decider_id = p_decider_id
          AND decider = p_decider
          AND final = TRUE
    ) INTO has_final_event;
    
    RETURN test_assert(
        has_final_event,
        format('%s - Stream should be final: decider_id=%s, decider=%s', 
               message, p_decider_id, p_decider)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that an event stream is not final
CREATE OR REPLACE FUNCTION test_assert_stream_not_final(
    p_decider_id TEXT,
    p_decider TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    has_final_event BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM events
        WHERE decider_id = p_decider_id
          AND decider = p_decider
          AND final = TRUE
    ) INTO has_final_event;
    
    RETURN test_assert(
        NOT has_final_event,
        format('%s - Stream should not be final: decider_id=%s, decider=%s', 
               message, p_decider_id, p_decider)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that previous_id chain is valid for a decider stream
CREATE OR REPLACE FUNCTION test_assert_previous_id_chain_valid(
    p_decider_id TEXT,
    p_decider TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    chain_violations INTEGER;
    first_event_violations INTEGER;
BEGIN
    -- Check that all events except the first have a valid previous_id
    SELECT COUNT(*) INTO chain_violations
    FROM events e1
    WHERE e1.decider_id = p_decider_id
      AND e1.decider = p_decider
      AND e1.previous_id IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM events e2
          WHERE e2.event_id = e1.previous_id
            AND e2.decider_id = e1.decider_id
            AND e2.decider = e1.decider
      );
    
    -- Check that exactly one event has null previous_id (the first event)
    SELECT COUNT(*) INTO first_event_violations
    FROM (
        SELECT COUNT(*) as null_previous_count
        FROM events
        WHERE decider_id = p_decider_id
          AND decider = p_decider
          AND previous_id IS NULL
    ) counts
    WHERE null_previous_count != 1;
    
    RETURN test_assert(
        chain_violations = 0 AND first_event_violations = 0,
        format('%s - Previous ID chain should be valid: decider_id=%s, decider=%s (chain_violations=%s, first_event_violations=%s)', 
               message, p_decider_id, p_decider, chain_violations, first_event_violations)
    );
END;
$$ LANGUAGE plpgsql;

-- API: Assert that JSON data contains expected key-value pairs
CREATE OR REPLACE FUNCTION test_assert_json_contains(
    actual_json JSONB,
    expected_key TEXT,
    expected_value TEXT,
    message TEXT
)
    RETURNS BOOLEAN AS
$$
DECLARE
    actual_value TEXT;
BEGIN
    actual_value := actual_json ->> expected_key;
    
    RETURN test_assert_equals(
        expected_value,
        actual_value,
        format('%s - JSON should contain key=%s with value=%s', 
               message, expected_key, expected_value)
    );
END;
$$ LANGUAGE plpgsql;
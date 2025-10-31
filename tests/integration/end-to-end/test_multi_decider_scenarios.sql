-- ##########################################################################################
-- ######                    MULTI DECIDER SCENARIOS TEST                         ######
-- ##########################################################################################

-- Simple test for multi decider scenarios
\echo 'Testing multi decider scenarios...'

-- Load test framework
\i tests/utils/test-helpers.sql
\i tests/utils/assertions.sql

-- Clear any existing test data
DELETE FROM locks WHERE view LIKE 'multi_%';
DELETE FROM views WHERE view LIKE 'multi_%';
DELETE FROM events WHERE decider_id LIKE 'multi_%';
DELETE FROM deciders WHERE decider LIKE 'multi_%';
SELECT test_clear_results();

SELECT test_setup('test_multi_decider_scenarios', 'integration');

-- Test: Multiple decider types with different views
DO $$
DECLARE
    order_event_id UUID := gen_random_uuid();
    payment_event_id UUID := gen_random_uuid();
    order_command_id UUID := gen_random_uuid();
    payment_command_id UUID := gen_random_uuid();
    order_events INTEGER;
    payment_events INTEGER;
    total_views INTEGER;
BEGIN
    -- Setup different decider types
    PERFORM register_decider_event('order_decider', 'order_created', 'Order creation event', 1);
    PERFORM register_decider_event('payment_decider', 'payment_processed', 'Payment processing event', 1);
    
    -- Setup multiple views with different configurations
    PERFORM register_view('multi_order_view'::TEXT, (NOW() - INTERVAL '1 hour')::TIMESTAMP, 300::BIGINT, 2::BIGINT, NULL::TEXT);
    PERFORM register_view('multi_payment_view'::TEXT, (NOW() - INTERVAL '1 hour')::TIMESTAMP, 600::BIGINT, 5::BIGINT, NULL::TEXT);
    PERFORM register_view('multi_analytics_view'::TEXT, (NOW() - INTERVAL '1 hour')::TIMESTAMP, 120::BIGINT, 1::BIGINT, NULL::TEXT);
    
    -- Create events for different deciders
    PERFORM append_event('order_created', order_event_id, 'order_decider', 'multi_order_001', '{"order_id": "001", "amount": 100}', order_command_id, NULL, 1);
    PERFORM append_event('payment_processed', payment_event_id, 'payment_decider', 'multi_payment_001', '{"payment_id": "001", "status": "success"}', payment_command_id, NULL, 1);
    
    -- Verify events for each decider type
    SELECT COUNT(*) INTO order_events FROM events WHERE decider = 'order_decider';
    SELECT COUNT(*) INTO payment_events FROM events WHERE decider = 'payment_decider';
    
    IF order_events != 1 THEN
        RAISE EXCEPTION 'Test failed: Expected 1 order event, got %', order_events;
    END IF;
    
    IF payment_events != 1 THEN
        RAISE EXCEPTION 'Test failed: Expected 1 payment event, got %', payment_events;
    END IF;
    
    -- Verify views are registered
    SELECT COUNT(*) INTO total_views FROM views WHERE view LIKE 'multi_%';
    
    IF total_views != 3 THEN
        RAISE EXCEPTION 'Test failed: Expected 3 views, got %', total_views;
    END IF;
    
    RAISE NOTICE 'Test PASSED: Multi decider scenarios work (% order events, % payment events, % views)', order_events, payment_events, total_views;
END;
$$;

SELECT test_cleanup('test_multi_decider_scenarios');

\echo 'multi decider scenarios tests completed successfully';
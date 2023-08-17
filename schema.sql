-- ##########################################################################################
-- ##########################################################################################
-- ######                                  EVENT SOURCING                              ######
-- ##########################################################################################
-- ##########################################################################################

-- In this event store, an event cannot exist without an decider/entity
-- The deciders table controls the decider and event names/types that can be used in the events table itself through the use of composite foreign keys.
-- It must be populated before events can be appended to the main table called events.
CREATE TABLE IF NOT EXISTS deciders
(
    -- decider name/type
    "decider" TEXT NOT NULL,
    -- event name/type that this decider can publish
    "event"   TEXT NOT NULL,
    PRIMARY KEY ("decider", "event")
);

-- The events table is designed to allow multiple concurrent, uncoordinated writers to safely create events.
-- It expects the client to know the difference between an decider's first event and subsequent events (previous_id), effectively enabling optimistic locking.
-- Multiple constraints are applied to this table to ensure bad events do not make their way into the system.
-- This includes duplicated events, incorrect naming (event and decider names cannot be misspelled, and client cannot insert an event from the wrong decider) and ensured sequential events.
CREATE TABLE IF NOT EXISTS events
(
    -- event name/type. Part of a composite foreign key to `deciders`
    "event"       TEXT    NOT NULL,
    -- event ID. This value is used by the next event as it's `previous_id` value to implement optimistic locking effectively.
    "event_id"    UUID    NOT NULL UNIQUE,
    -- decider name/type. Part of a composite foreign key to `deciders`
    "decider"     TEXT    NOT NULL,
    -- identifier for the decider
    "decider_id"  UUID    NOT NULL,
    -- event data in JSON format
    "data"        JSONB   NOT NULL,
    -- command ID causing this event
    "command_id"  UUID    NOT NULL,
    -- previous event uuid; null for first event; null does not trigger UNIQUE constraint; we defined a function `check_first_event_for_decider`
    "previous_id" UUID UNIQUE,
    -- indicator if the event stream for the `decider_id` is final
    "final"       BOOLEAN NOT NULL         DEFAULT FALSE,
    -- The timestamp of the event insertion.
    "created_at"  TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    -- ordering sequence/offset for all events, in all deciders.
    "offset"      BIGSERIAL PRIMARY KEY,
    FOREIGN KEY ("decider", "event") REFERENCES deciders ("decider", "event")
);

CREATE INDEX IF NOT EXISTS decider_index ON events ("decider_id", "decider");

-- SIDE EFFECT (rule): immutable decider - ignore deleting already registered events
CREATE OR REPLACE RULE ignore_delete_decider_events AS ON DELETE TO deciders
    DO INSTEAD NOTHING;

-- SIDE EFFECT (rule): immutable decider - ignore updating already registered events
CREATE OR REPLACE RULE ignore_update_decider_events AS ON UPDATE TO deciders
    DO INSTEAD NOTHING;

-- SIDE EFFECT (rule): immutable events - ignore delete
CREATE OR REPLACE RULE ignore_delete_events AS ON DELETE TO events
    DO INSTEAD NOTHING;

-- SIDE EFFECT (rule): immutable events - ignore update
CREATE OR REPLACE RULE ignore_update_events AS ON UPDATE TO events
    DO INSTEAD NOTHING;

-- SIDE EFFECT (trigger): can only append events if the decider_id stream is not finalized already
CREATE OR REPLACE FUNCTION check_final_event_for_decider() RETURNS trigger AS
'
    BEGIN
        IF EXISTS(SELECT 1
                  FROM events
                  WHERE NEW.decider_id = decider_id
                    AND TRUE = final
                    AND NEW.decider = decider)
        THEN
            RAISE EXCEPTION ''last event for this decider stream is already final. the stream is closed, you can not append events to it.'';
        END IF;
        RETURN NEW;
    END;
'
    LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS t_check_final_event_for_decider ON events;
CREATE TRIGGER t_check_final_event_for_decider
    BEFORE INSERT
    ON events
    FOR EACH ROW
EXECUTE FUNCTION check_final_event_for_decider();

-- SIDE EFFECT (trigger): Can only use null previousId for the first event in decider
CREATE OR REPLACE FUNCTION check_first_event_for_decider() RETURNS trigger AS
'
    BEGIN
        IF (NEW.previous_id IS NULL
            AND EXISTS(SELECT 1
                       FROM events
                       WHERE NEW.decider_id = decider_id
                         AND NEW.decider = decider))
        THEN
            RAISE EXCEPTION ''previous_id can only be null for the first decider event'';
        END IF;
        RETURN NEW;
    END;
'
    LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS t_check_first_event_for_decider ON events;
CREATE TRIGGER t_check_first_event_for_decider
    BEFORE INSERT
    ON events
    FOR EACH ROW
EXECUTE FUNCTION check_first_event_for_decider();


-- SIDE EFFECT (trigger): previousId must be in the same decider as the event
CREATE OR REPLACE FUNCTION check_previous_id_in_same_decider() RETURNS trigger AS
'
    BEGIN
        IF (NEW.previous_id IS NOT NULL
            AND NOT EXISTS(SELECT 1
                           FROM events
                           WHERE NEW.previous_id = event_id
                             AND NEW.decider_id = decider_id
                             AND NEW.decider = decider))
        THEN
            RAISE EXCEPTION ''previous_id must be in the same decider'';
        END IF;
        RETURN NEW;
    END;
'
    LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS t_check_previous_id_in_same_decider ON events;
CREATE TRIGGER t_check_previous_id_in_same_decider
    BEFORE INSERT
    ON events
    FOR EACH ROW
EXECUTE FUNCTION check_previous_id_in_same_decider();

-- ##########################################################################################
-- ##########################################################################################
-- ######                                  EVENT STREAMING                             ######
-- ##########################################################################################
-- ##########################################################################################

-- The views table is a registry of all views/subscribers that are able to subscribe to all events with a "pooling_delay" frequency.
-- You can not start consuming events without previously registering the view.
-- see: `stream_events` function
CREATE TABLE IF NOT EXISTS views
(
    -- view identifier/name
    "view"          TEXT,
    -- pooling_delay represent the frequency of pooling the database for the new events / 500 ms by default
    "pooling_delay" BIGINT                   DEFAULT 500   NOT NULL,
    -- the point in time form where the event streaming/pooling should start / NOW is by default, but you can specify the binging of time if you want
    "start_at"      TIMESTAMP                DEFAULT NOW() NOT NULL,
    -- the timestamp of the view insertion.
    "created_at"    TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    -- the timestamp of the view update.
    "updated_at"    TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    PRIMARY KEY ("view")
);

-- The locks table is designed to allow multiple concurrent, uncoordinated consumers to safely read/stream events per view
-- It can be only one transaction consuming events for the same decider_id/partition, but many transactions can concurrently consume events belonging to different decider_id's, without contention.
-- see: `stream_events` function
CREATE TABLE IF NOT EXISTS locks
(
    -- view identifier/name
    "view"         TEXT                                                    NOT NULL,
    -- business identifier for the decider
    "decider_id"   UUID                                                    NOT NULL,
    -- current offset of the event stream for decider_id
    "offset"       BIGINT                                                  NOT NULL,
    -- the offset of the last event being processed
    "last_offset"  BIGINT                                                  NOT NULL,
    -- a lock / is this event stream for particular decider_id locked for reading or not
    "locked_until" TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '1ms' NOT NULL,
    -- an indicator if the offset is final / offset will not grow any more
    "offset_final" BOOLEAN                                                 NOT NULL,
    -- the timestamp of the view insertion.
    "created_at"   TIMESTAMP WITH TIME ZONE DEFAULT NOW()                  NOT NULL,
    -- the timestamp of the view update.
    "updated_at"   TIMESTAMP WITH TIME ZONE DEFAULT NOW()                  NOT NULL,
    PRIMARY KEY ("view", "decider_id"),
    FOREIGN KEY ("view") REFERENCES views ("view") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS locks_index ON locks ("decider_id", "locked_until", "last_offset");

-- SIDE EFFECT:  before_update_views_table - automatically bump "updated_at" when modifying a view
CREATE OR REPLACE FUNCTION "before_update_views_table"() RETURNS trigger AS
'
    BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
    END;
'
    LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "t_before_update_views_table" ON "views";
CREATE TRIGGER "t_before_update_views_table"
    BEFORE UPDATE
    ON "views"
    FOR EACH ROW
EXECUTE FUNCTION "before_update_views_table"();

-- SIDE EFFECT:  before_update_locks_table - automatically bump "updated_at" when modifying a lock
CREATE OR REPLACE FUNCTION "before_update_locks_table"() RETURNS trigger AS
'
    BEGIN
        NEW.updated_at = NOW();
        RETURN NEW;
    END;
'
    LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS "t_before_update_locks_table" ON "locks";
CREATE TRIGGER "t_before_update_locks_table"
    BEFORE UPDATE
    ON "locks"
    FOR EACH ROW
EXECUTE FUNCTION "before_update_locks_table"();

--  SIDE EFFECT: after appending a new event (with new decider_id), the lock is upserted
CREATE OR REPLACE FUNCTION on_insert_on_events() RETURNS trigger AS
'
    BEGIN

        INSERT INTO locks
        SELECT t1.view        AS view,
               NEW.decider_id AS decider_id,
               NEW.offset     AS offset,
               0              AS last_offset,
               NOW()          AS locked_until,
               NEW.final      AS offset_final
        FROM views AS t1
        ON CONFLICT ON CONSTRAINT "locks_pkey" DO UPDATE SET "offset" = NEW."offset", offset_final = NEW.final;
        RETURN NEW;
    END;
'
    LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS t_on_insert_on_events ON events;
CREATE TRIGGER t_on_insert_on_events
    AFTER INSERT
    ON events
    FOR EACH ROW
EXECUTE FUNCTION on_insert_on_events();



-- SIDE EFFECT: after upserting a views, all the locks should be re-upserted so to keep the correct matrix of `view-deciderId` locks
CREATE OR REPLACE FUNCTION on_insert_or_update_on_views() RETURNS trigger AS
'
    BEGIN
        INSERT INTO locks
        SELECT NEW."view"    AS "view",
               t1.decider_id AS decider_id,
               t1.max_offset AS "offset",
               COALESCE(
                       (SELECT t2."offset" - 1 AS "offset"
                        FROM events AS t2
                        WHERE t2.decider_id = t1.decider_id
                          AND t2.created_at >= NEW.start_at
                        ORDER BY t2."offset" ASC
                        LIMIT 1),
                       (SELECT t2."offset" AS "offset"
                        FROM events AS t2
                        WHERE t2.decider_id = t1.decider_id
                        ORDER BY "t2"."offset" DESC
                        LIMIT 1)
                   )         AS last_offset,
               NOW()         AS locked_until,
               t1.final      AS offset_final
        FROM (SELECT DISTINCT ON (decider_id) decider_id AS decider_id,
                                              "offset"   AS max_offset,
                                              final      AS final
              FROM events
              ORDER BY decider_id, "offset" DESC) AS t1
        ON CONFLICT ON CONSTRAINT "locks_pkey"
            DO UPDATE
            SET "offset"    = EXCLUDED."offset",
                last_offset = EXCLUDED.last_offset,
                offset_final = EXCLUDED.offset_final;
        RETURN NEW;
    END;
' LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS t_on_insert_or_update_on_views ON "views";
CREATE TRIGGER t_on_insert_or_update_on_views
    AFTER INSERT OR UPDATE
    ON "views"
    FOR EACH ROW
EXECUTE FUNCTION on_insert_or_update_on_views();

-- #######################################################################################
-- #######################################################################################
-- ######                                 API FUNCTIONS                            #######
-- #######################################################################################
-- #######################################################################################

-- #######################################################################################
-- ######                                 EVENT SOURCING                            ######
-- #######################################################################################


-- Register the type of event that this `decider` is able to publish/store
-- Event can not be inserted into `event` table without the matching event being registered previously. It is controlled by the 'Foreign Key' constraint on the `event` table
-- Example of usage: SELECT * from register_decider_event('decider1', 'event1')
CREATE OR REPLACE FUNCTION register_decider_event(v_decider TEXT, v_event TEXT)
    RETURNS SETOF deciders AS
'
    BEGIN
        RETURN QUERY
            INSERT INTO deciders (decider, event) VALUES (v_decider, v_event) RETURNING *;
    END;
' LANGUAGE plpgsql;

-- Append/Insert new 'event'
-- Example of usage: SELECT * from append_event('event1', '21e19516-9bda-11ed-a8fc-0242ac120002', 'decider1', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002', '{}', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002', null)
CREATE OR REPLACE FUNCTION append_event(v_event TEXT, v_event_id UUID, v_decider TEXT, v_decider_id UUID, v_data JSONB,
                                        v_command_id UUID, v_previous_id UUID)
    RETURNS SETOF events AS
'
    BEGIN
        RETURN QUERY INSERT INTO events (event, event_id, decider, decider_id, data, command_id, previous_id)
            VALUES (v_event, v_event_id, v_decider, v_decider_id, v_data, v_command_id, v_previous_id)
            RETURNING *;
    END;
' LANGUAGE plpgsql;

-- Get events by decider_id
-- Used by the Decider/Entity to get list of events from where it can source its own state
-- Example of usage: SELECT * FROM get_events('f156a3c4-9bd8-11ed-a8fc-0242ac120002')
CREATE OR REPLACE FUNCTION get_events(v_decider_id UUID)
    RETURNS SETOF events AS
'
    BEGIN
        RETURN QUERY SELECT *
                     FROM events
                     WHERE decider_id = v_decider_id
                     ORDER BY "offset";
    END;
' LANGUAGE plpgsql;

-- #######################################################################################
-- ######                                EVENT STREAMING                            ######
-- #######################################################################################

-- Register a `view` (responsible for streaming events to concurrent consumers)
-- Once the `view` is registered you can start `read_events` which will stream events by pooling database with delay, filtering `events` that are created after `start_at` timestamp
-- Example of usage: SELECT * from register_view('view1', 500, '2023-01-23 12:17:17.078384')
CREATE OR REPLACE FUNCTION register_view(v_view TEXT, v_pooling_delay BIGINT, v_start_at TIMESTAMP)
    RETURNS SETOF "views" AS
'
    BEGIN
        RETURN QUERY
            INSERT INTO "views" ("view", pooling_delay, start_at)
                VALUES (v_view, v_pooling_delay, v_start_at) RETURNING *;
    END;
' LANGUAGE plpgsql;

-- Get event(s) for the view - event streaming to concurrent consumers in a safe way
-- Concurrent Views/Subscribers can not stream/read events from one decider_id stream (partition) at the same time, because `lock` is preventing it.
-- They can read events concurrently from different decider_id streams (partitions) by preserving the ordering of events within decider_id stream (partition) only!
-- Example of usage: SELECT * from stream_events('view1')
CREATE OR REPLACE FUNCTION stream_events(v_view_name TEXT)
    RETURNS SETOF events AS
'
    DECLARE
        v_last_offset INTEGER;
        v_decider_id  UUID;
    BEGIN
        -- Check if there are events with a greater id than the last_offset and acquire lock on views table/row for the first decider_id/stream you can find
        SELECT decider_id, last_offset
        INTO v_decider_id, v_last_offset
        FROM locks
        WHERE view = v_view_name
          AND locked_until < NOW() -- locked = false
          AND last_offset < "offset"
        ORDER BY "offset"
        LIMIT 1 FOR UPDATE SKIP LOCKED;

        -- Update views locked status to true
        UPDATE locks
        SET locked_until = NOW() + INTERVAL ''5m'' -- locked = true, for next 5 minutes
        WHERE view = v_view_name
          AND locked_until < NOW() -- locked = false
          AND decider_id = v_decider_id;

        -- Return the events that have not been locked yet
        RETURN QUERY SELECT *
                     FROM events
                     WHERE decider_id = v_decider_id
                       AND "offset" > v_last_offset
                     ORDER BY "offset"
                     LIMIT 1;
    END;
' LANGUAGE plpgsql;

-- Acknowledge that event with `decider_id` and `offset` is processed by the view
-- Essentially, it will unlock current decider_id stream (partition) for further reading
-- Example of usage: SELECT * from ack_event('view1', 'f156a3c4-9bd8-11ed-a8fc-0242ac120002', 1)
CREATE OR REPLACE FUNCTION ack_event(v_view TEXT, v_decider_id uuid, v_offset BIGINT)
    RETURNS SETOF "locks" AS
'
    BEGIN
        -- Update locked status to false
        RETURN QUERY
            UPDATE locks
                SET locked_until = NOW(), -- locked = false,
                    last_offset = v_offset
                WHERE "view" = v_view
                    AND decider_id = v_decider_id
                RETURNING *;
    END;
' LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION nack_event(v_view TEXT, v_decider_id TEXT)
    RETURNS SETOF "locks" AS
'
    BEGIN
        -- Nack: Update locked status to false, without updating the offset
        RETURN QUERY
            UPDATE locks
                SET locked_until = NOW() -- locked = false
                WHERE "view" = v_view
                    AND decider_id = v_decider_id
                RETURNING *;
    END;
' LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION schedule_nack_event(v_view TEXT, v_decider_id TEXT, v_milliseconds BIGINT)
    RETURNS SETOF "locks" AS
'
    BEGIN
        -- Schedule the nack
        RETURN QUERY
            UPDATE locks
                SET "locked_until" = NOW() + (v_milliseconds || ''ms'')::INTERVAL
                WHERE "view" = v_view
                    AND decider_id = v_decider_id
                RETURNING *;
    END;
' LANGUAGE plpgsql;
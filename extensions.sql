-- With this two extensions we enabled the event streaming to the edge-functions/event-handlers, automatically.
-- https://github.com/citusdata/pg_cron
-- https://github.com/supabase/pg_net
-- Your application does not have ot call `stream_events('view1')` function any more, `cron.job` will run `SELECT * from stream_events('view1');` for you, and publish event(s) to your edge-functions/http endpoints automatically. So, the database is doing all the job.
-- The `cron` job is managed(created/deleted) by triggers on the `view` table. So, whenever you register a new View, the cron job will be created automatically.

-- #######################################################################################
-- ######                                pg_NET extension                          ######
-- #######################################################################################
create extension if not exists "pg_net" with schema "public";


-- #######################################################################################
-- ######                                pg_CRON extension                          ######
-- #######################################################################################

-- enable 'pg_cron' extension
create extension if not exists "pg_cron";

-- #######################################################################################
-- ######                             Stream events to the Edge                     ######
-- #######################################################################################

-- API: Create a function to stream events to a view/event handler/edge function(s).
-- The view/event handler is an HTTP endpoint/edge function that receives the events.
-- example: SELECT schedule_events('view', 'view-cron', '5 seconds');
-- unschedule: SELECT cron.unschedule('event-handler-cron');
CREATE OR REPLACE FUNCTION schedule_events(v_view TEXT, v_job_name TEXT, v_schedule TEXT)
    RETURNS bigint AS
$$
DECLARE
    sql_statement TEXT;
BEGIN
    -- Construct the dynamic SQL statement
    sql_statement := '
        WITH event_result AS (
            SELECT *
            FROM stream_events(''' || v_view || ''')
            LIMIT 1
        )
        SELECT
            net.http_post(
                url:=''https://mkqwnwwkrupyrqnqsomg.supabase.co/functions/v1/event-handler'',
                body:=jsonb_build_object(''view'', ''' || v_view || ''', ''decider_id'', event_result.decider_id, ''offset'', event_result.offset, ''data'', event_result.data)
            ) AS request_id
        FROM event_result
    ';

    -- Execute the dynamic SQL statement
    EXECUTE sql_statement;

    -- Schedule the dynamic SQL statement to run at the specified interval
    RETURN cron.schedule(v_job_name, v_schedule, sql_statement);
END;
$$ LANGUAGE plpgsql;


-- Trigger: Create a trigger function that will activate streaming events to a view/event handler automatically.
CREATE OR REPLACE FUNCTION on_insert_on_views() RETURNS trigger AS
'
    BEGIN
        -- Create the cron job. Stream events to the view/event handler every `NEW.pooling_delay` seconds
        PERFORM schedule_events(NEW.view, NEW.view, NEW.pooling_delay || '' seconds'');
        -- If you do not want to use cron.job_run_details at all, then you can add cron.log_run = off to postgresql.conf.
        -- or, delete old cron.job_run_details records of the current view, every day at noon
        PERFORM cron.schedule(''delete'' || NEW.view, ''0 12 * * *'',
                              $$DELETE FROM cron.job_run_details USING cron.job WHERE jobid = cron.job.jobid AND cron.job.jobname = NEW.view AND end_time < now() - interval ''1 days''$$);
        RETURN NEW;
    END;
' LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS t_on_insert_on_views ON "views";
CREATE TRIGGER t_on_insert_on_views
    AFTER INSERT
    ON "views"
    FOR EACH ROW
EXECUTE FUNCTION on_insert_on_views();

-- Create a trigger function to stop the cron job, and stop streaming events to a view/event handler.
CREATE OR REPLACE FUNCTION on_delete_on_views() RETURNS trigger AS
'
    BEGIN
        PERFORM cron.unschedule(OLD.view);
        RETURN NEW;
    END;
' LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS t_on_delete_on_views ON "views";
CREATE TRIGGER t_on_delete_on_views
    AFTER DELETE
    ON "views"
    FOR EACH ROW
EXECUTE FUNCTION on_delete_on_views();

-- =============================================================================
-- checkpoint.sql -- WRITE: upsert ONE run checkpoint into BRONZE.RUN_CONTROL.
--
-- NOT read-only. Do NOT run via scripts/check.sh (that wrapper is for inspection).
-- Run via scripts/checkpoint.sh, which supplies ALL FOUR -D variables
-- (run_id, step, status, note) -- the Snowflake CLI errors on any unsubstituted
-- <% ... %> placeholder, so the wrapper always passes defaults.
--
-- WHY: resume the WORK, not the session. Snowflake sessions are not resumable
-- across a connection drop; a caller-supplied STABLE run_id + step is upserted
-- here (one row per (run_id, step)). A fresh window reads progress via
-- scripts/sql/show_run_control.sql and continues from the last checkpoint.
-- session_id + query_tag are recorded for dual-instance provenance (two windows
-- writing the same (run_id, step) show up in the show_run_control.sql smell test).
--
-- Requires ARTWORK_DB.BRONZE.RUN_CONTROL (created by
-- infrastructure/create_run_control.sql via `make infra`). Operational DML only --
-- it creates NO objects, so it correctly lives OUTSIDE the manifest/orchestrator.
-- =============================================================================

USE ROLE ARTWORK_ADMIN;

-- Tag this write so QUERY_HISTORY can be correlated to the run even if the UI
-- stops rendering. (Each `snow sql` call is its own session, so this tags the
-- checkpoint write itself; the durable correlation lives in the query_tag column.)
ALTER SESSION SET QUERY_TAG = 'artworkdb:run-<% run_id %>';

MERGE INTO ARTWORK_DB.BRONZE.RUN_CONTROL t
USING (SELECT '<% run_id %>' AS run_id, '<% step %>' AS step) s
   ON t.run_id = s.run_id AND t.step = s.step
WHEN MATCHED THEN UPDATE SET
    status     = '<% status %>',
    note       = '<% note %>',
    session_id = CURRENT_SESSION(),
    query_tag  = 'artworkdb:run-<% run_id %>',
    updated_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT
    (run_id, step, status, note, session_id, query_tag)
    VALUES ('<% run_id %>', '<% step %>', '<% status %>', '<% note %>',
            CURRENT_SESSION(), 'artworkdb:run-<% run_id %>');

-- Echo the row back so the caller sees the persisted checkpoint.
SELECT run_id, step, status, note, session_id, query_tag, updated_at
FROM ARTWORK_DB.BRONZE.RUN_CONTROL
WHERE run_id = '<% run_id %>' AND step = '<% step %>';

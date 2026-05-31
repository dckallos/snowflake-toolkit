-- =============================================================================
-- show_active_sessions.sql -- READ-ONLY ad-hoc check.
-- Detect concurrent Cortex Code windows / other live sessions under YOUR user.
--
-- Run via: scripts/check.sh   (defaults to this file)
-- Safe to run anytime; makes no changes. Uses INFORMATION_SCHEMA (low latency),
-- NOT ACCOUNT_USAGE (which lags up to ~3h).
--
-- If row count > 0, another session has been active in the last 5 minutes ->
-- likely a second Cortex window. To stop one (ACCOUNTADMIN), see the commented
-- abort block at the bottom: copy the SESSION_ID and run those two statements.
-- =============================================================================

-- 1) This session (the one you are keeping). Never abort this id.
SELECT CURRENT_SESSION() AS this_session_id,
       CURRENT_USER()    AS this_user,
       CURRENT_ROLE()    AS this_role;

-- 2) OTHER sessions for the current user with activity in the last 5 minutes.
SELECT
    SESSION_ID,
    COUNT(*)                       AS queries_last_5min,
    MIN(START_TIME)                AS first_query,
    MAX(START_TIME)                AS last_query,
    ARRAY_AGG(DISTINCT QUERY_TAG)  AS query_tags
FROM TABLE(ARTWORK_DB.INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER(RESULT_LIMIT => 1000))
WHERE START_TIME >= DATEADD('minute', -5, CURRENT_TIMESTAMP())
  AND SESSION_ID <> CURRENT_SESSION()
GROUP BY SESSION_ID
ORDER BY last_query DESC;

-- ---------------------------------------------------------------------------
-- TO ABORT A SPECIFIC OTHER SESSION (ACCOUNTADMIN): copy its SESSION_ID from the
-- result above and run these two statements (cancel queries first, then abort).
-- Abort is asynchronous; a live client may reconnect, so also CLOSE that window.
-- ---------------------------------------------------------------------------
-- SELECT SYSTEM$CANCEL_ALL_QUERIES(<other_session_id>);
-- SELECT SYSTEM$ABORT_SESSION(<other_session_id>);

# Phase 5 H6 — Dashboard rollup query plans

Captured against the development SQLite DB on 2026-05-17 after adding
`index_messages_on_created_at` (migration
`20260517121237_add_created_at_index_to_messages.rb`).

Queries reflect `Dashboard::Rollup` (`app/models/dashboard/rollup.rb`)
materialized into a representative joined scope:

```ruby
scope = Message.joins(:chat_session)
               .where(chat_sessions: { user_id: 1 })
               .where(status: :completed)
               .where(created_at: 14.days.ago..)
```

Plans were captured via `EXPLAIN QUERY PLAN <sql>` through
`ActiveRecord::Base.connection.execute` in `bin/rails runner`.

## tokens_by_day

```sql
SELECT date(messages.created_at),
       SUM(messages.prompt_tokens + messages.completion_tokens) AS tokens,
       SUM(messages.cost_usd) AS cost
FROM "messages"
INNER JOIN "chat_sessions" ON "chat_sessions"."id" = "messages"."chat_session_id"
WHERE "chat_sessions"."user_id" = 1
  AND "messages"."status" = 2
  AND "messages"."created_at" >= '...'
GROUP BY date(messages.created_at)
```

**Before index:**
```
SEARCH chat_sessions USING COVERING INDEX index_chat_sessions_on_user_id (user_id=?)
SEARCH messages USING INDEX index_messages_on_chat_session_id_and_created_at (chat_session_id=? AND created_at>?)
USE TEMP B-TREE FOR GROUP BY
```

**After index:**
```
SEARCH chat_sessions USING COVERING INDEX index_chat_sessions_on_user_id (user_id=?)
SEARCH messages USING INDEX index_messages_on_chat_session_id_and_created_at (chat_session_id=? AND created_at>?)
USE TEMP B-TREE FOR GROUP BY
```

Identical. The planner keeps the existing compound index because
`chat_session_id` is the leading equality predicate from the join nest.

## cost_by_model

```sql
SELECT "messages"."model", SUM(messages.cost_usd) AS cost
FROM "messages"
INNER JOIN "chat_sessions" ON "chat_sessions"."id" = "messages"."chat_session_id"
WHERE "chat_sessions"."user_id" = 1
  AND "messages"."status" = 2
  AND "messages"."created_at" >= '...'
GROUP BY "messages"."model"
```

**Before index:**
```
SEARCH chat_sessions USING COVERING INDEX index_chat_sessions_on_user_id (user_id=?)
SEARCH messages USING INDEX index_messages_on_chat_session_id_and_created_at (chat_session_id=? AND created_at>?)
USE TEMP B-TREE FOR GROUP BY
```

**After index:**
```
SEARCH chat_sessions USING COVERING INDEX index_chat_sessions_on_user_id (user_id=?)
SEARCH messages USING INDEX index_messages_on_chat_session_id_and_created_at (chat_session_id=? AND created_at>?)
USE TEMP B-TREE FOR GROUP BY
```

Identical.

## cost_by_session

```sql
SELECT "messages"."chat_session_id", SUM(messages.cost_usd) AS cost
FROM "messages"
INNER JOIN "chat_sessions" ON "chat_sessions"."id" = "messages"."chat_session_id"
WHERE "chat_sessions"."user_id" = 1
  AND "messages"."status" = 2
  AND "messages"."created_at" >= '...'
GROUP BY "messages"."chat_session_id"
ORDER BY SUM(messages.cost_usd) DESC
LIMIT 10
```

**Before index:**
```
SEARCH chat_sessions USING COVERING INDEX index_chat_sessions_on_user_id (user_id=?)
SEARCH messages USING INDEX index_messages_on_chat_session_id_and_created_at (chat_session_id=? AND created_at>?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR ORDER BY
```

**After index:**
```
SEARCH chat_sessions USING COVERING INDEX index_chat_sessions_on_user_id (user_id=?)
SEARCH messages USING INDEX index_messages_on_chat_session_id_and_created_at (chat_session_id=? AND created_at>?)
USE TEMP B-TREE FOR GROUP BY
USE TEMP B-TREE FOR ORDER BY
```

Identical.

## Notes

- All three rollup queries already use index access (`SEARCH messages
  USING INDEX …`); none degrade to `SCAN messages`. The compound index
  `index_messages_on_chat_session_id_and_created_at` from Phase 1 fully
  covers the dashboard's joined access pattern: SQLite filters by
  `chat_session_id` from the join, then uses the trailing `created_at`
  column of the compound index as a range predicate for the 14-day
  window.
- The planner did **not** switch to `index_messages_on_created_at` after
  the migration — running `ANALYZE` afterward did not change the plan
  either. This is the correct decision for the joined query: the
  standalone `created_at` index would force a separate intersection or
  more rows per chat_session bucket.
- The new index still earns its keep for **future per-user-wide queries
  that bypass the `chat_sessions` join** (e.g. a system-wide rollup,
  background sweeps, or a Phase 6+ admin dashboard that filters only by
  `created_at`). Without it, those queries would degrade to `SCAN
  messages`.
- The `date(messages.created_at)` group expression cannot be indexed in
  SQLite without an expression index, which SQLite *does* support
  (`CREATE INDEX … ON messages (date(created_at))`) but Rails'
  `add_index` does not generate by default. Today's
  `USE TEMP B-TREE FOR GROUP BY` is acceptable at our row counts (≤14
  days × per-user message volume).
- **Postgres path:** if/when we move off SQLite, an expression index
  `CREATE INDEX index_messages_on_date_created_at ON messages
  ((date(created_at)));` would let the planner skip the function
  evaluation and the temp B-tree for `tokens_by_day` entirely.
- **ANALYZE:** for SQLite, the planner statistics live in `sqlite_stat1`
  and only update on `ANALYZE`. We ran it after the migration as a
  sanity check; it had no effect on these plans because the leading
  index column for the join is fixed by the query shape, not by
  statistics.

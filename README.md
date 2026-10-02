# RideSync – Global Ride-Hailing Network

A polyglot-persistence demo combining **PostgreSQL** (structured, transactional data — riders, vehicles, trips, wallet audit logs) with **MongoDB** (unstructured/semi-structured data — vehicle metadata, trip reviews, real-time telemetry).

---

## 1. Prerequisites

- PostgreSQL 13+ (uses `REFRESH MATERIALIZED VIEW CONCURRENTLY`, partial indexes, PL/pgSQL procedures with `CALL`)
- MongoDB 5+ / `mongosh` (uses `$geoNear`, `$facet`, TTL indexes, 2dsphere indexes)
- Python 3.9+

Install Python dependencies:

```bash
pip install -r requirements.txt
```

`requirements.txt` includes `psycopg2-binary`, `pymongo`, `faker`, `python-dotenv`.

> **Note:** `postgres_seeder.py` and `mongo_seeder.py` currently hardcode DB credentials (`PG_CONFIG`, `MONGO_URI`) at the top of each file. Edit these to match your local setup before running (host, port, dbname, user, password).

---

## 2. PostgreSQL Setup

Run the SQL files **in this order** against an empty `ridesync_db` database:

```bash
psql -U postgres -d ridesync_db -f 01_schema_ddl.sql
psql -U postgres -d ridesync_db -f 02_indexes.sql
psql -U postgres -d ridesync_db -f 03_triggers_and_audit.sql
psql -U postgres -d ridesync_db -f 04_stored_procedures.sql
psql -U postgres -d ridesync_db -f 05_materialized_views.sql
psql -U postgres -d ridesync_db -f 06_window_analytics.sql
```

| File | What it creates |
|---|---|
| `01_schema_ddl.sql` | Core tables: `riders`, `vehicles`, `trips`, `wallet_audit_logs`, with `CHECK` constraints (non-negative balances/fares, valid trip status, valid audit action types) |
| `02_indexes.sql` | FK support indexes, plus the partial unique index `idx_one_active_trip_per_rider` preventing a rider from having more than one active (`REQUESTED`/`IN TRANSIT`) trip |
| `03_triggers_and_audit.sql` | `fn_wallet_audit_log()` + `trg_wallet_audit`, firing `AFTER UPDATE OF wallet_balance ON riders` to insert a row into `wallet_audit_logs` |
| `04_stored_procedures.sql` | `sp_book_trip(...)` (atomic booking: debit wallet, insert trip, rollback on failure) and `sp_release_escrow(...)` (mark a trip `COMPLETED`, log the release) |
| `05_materialized_views.sql` | `mv_vehicle_lifetime_stats` (per-vehicle trip count + lifetime earnings) and `refresh_mv_vehicle_lifetime_stats()` for concurrent refresh |
| `06_window_analytics.sql` | `vw_vehicle_revenue_moving_avg` — 7-day moving average of daily fare revenue per vehicle, ranked with `DENSE_RANK()` |

### Calling the stored procedures

`sp_book_trip` and `sp_release_escrow` use explicit `COMMIT`/`ROLLBACK` inside the procedure body. This only works when the procedure is called **outside** an open transaction block (i.e. with autocommit on), for example:

```sql
CALL sp_book_trip('<rider_uuid>', '<vehicle_uuid>', 150.00, NULL, NULL);
```

Do **not** wrap the call in `BEGIN; ... COMMIT;` yourself — the procedure manages its own transaction.

### Refreshing the materialized view

```sql
SELECT refresh_mv_vehicle_lifetime_stats();
```

---

## 3. MongoDB Setup

```bash
mongosh --file 01_collections_and_indexes.js
```

Creates `VehicleMetadata`, `TripReviews`, `TelemetryPings`, a `2dsphere` index on `TelemetryPings.location`, and a TTL index on `TelemetryPings.created_at` (`expireAfterSeconds: 7200`, i.e. pings auto-expire after 2 hours).

---

## 4. Seeding Data

Seed Postgres **first** (Mongo seeding depends on Postgres IDs for foreign-key-consistent data):

```bash
python postgres_seeder.py
```

This creates riders, vehicles, `VehicleMetadata` documents (keyed by the same `vehicle_id` as Postgres), and simulates trip bookings via `sp_book_trip` / `sp_release_escrow`.

Then seed Mongo telemetry and reviews:

```bash
python mongo_seeder.py
```

This pulls completed trips and vehicle IDs back out of Postgres to generate realistic `TelemetryPings` (clustered around per-vehicle "home" locations) and `TripReviews`.

> Run `postgres_seeder.py` again only after truncating/recreating the schema — it does not clean up prior runs.

---

## 5. Running the Workflows

**Workflow 3 — Nearest available vehicle ($geoNear):**

```bash
mongosh --file 02_workflow_geonear.js
```

**Workflow 4 — Multi-faceted review analytics ($facet):**

```bash
mongosh --file 03_workflow4_facet.js
```

**Workflow 2 — Window analytics (already created as a view in step 2):**

```sql
SELECT * FROM vw_vehicle_revenue_moving_avg
WHERE vehicle_id = '<some_vehicle_uuid>'
ORDER BY revenue_date;
```

**Workflow 1 — Atomic booking:** see "Calling the stored procedures" above, or observe it running end-to-end inside `postgres_seeder.py`.

---

## 6. Performance / Explain Analysis

**PostgreSQL query plans:**

```bash
psql -U postgres -d ridesync_db -f pg_explain_queries.sql
```

Runs `EXPLAIN ANALYZE` against representative queries (indexed lookups, joins with date filters, aggregate scans, materialized view reads, window-function view reads, subquery comparisons) to sanity-check index usage.

**MongoDB execution stats + human-readable report:**

```bash
mongosh --file mongo_execution_stats.js
```

Runs `$geoNear`, availability counts, review analytics, and a metadata cross-reference (ratings joined to `VehicleMetadata`, optimized to `$lookup` only the final top-10 vehicle IDs rather than every review), printing full detail to the console and a condensed report to `mongo_output.txt`.

> This script writes to a relative path (`./performance/mongo_output.txt` on non-Windows shells, or `.\performance\mongo_output.txt` as currently hardcoded). Create a `performance/` directory next to where you run `mongosh` first, or edit `OUTPUT_FILE` in the script, or the write will fail with `ENOENT`.

Also requires an index on `VehicleMetadata.vehicle_id` for the cross-reference lookup to stay fast — add it if not already present:

```javascript
db.VehicleMetadata.createIndex({ vehicle_id: 1 })
```

---

## 7. Suggested End-to-End Run Order

```bash
# 1. Postgres schema
psql -U postgres -d ridesync_db -f 01_schema_ddl.sql
psql -U postgres -d ridesync_db -f 02_indexes.sql
psql -U postgres -d ridesync_db -f 03_triggers_and_audit.sql
psql -U postgres -d ridesync_db -f 04_stored_procedures.sql
psql -U postgres -d ridesync_db -f 05_materialized_views.sql
psql -U postgres -d ridesync_db -f 06_window_analytics.sql

# 2. Mongo collections/indexes
mongosh --file 01_collections_and_indexes.js

# 3. Seed data
python postgres_seeder.py
python mongo_seeder.py

# 4. Refresh the materialized view now that trips exist
psql -U postgres -d ridesync_db -c "SELECT refresh_mv_vehicle_lifetime_stats();"

# 5. Run the workflows
mongosh --file 02_workflow_geonear.js
mongosh --file 03_workflow4_facet.js
psql -U postgres -d ridesync_db -c "SELECT * FROM vw_vehicle_revenue_moving_avg LIMIT 20;"

# 6. Performance analysis
psql -U postgres -d ridesync_db -f pg_explain_queries.sql
mongosh --file mongo_execution_stats.js
```

---

## 8. Known Limitations

- "Escrow" is simulated by decrementing `wallet_balance` at booking time and logging `ESCROW_HOLD`/`ESCROW_RELEASE` action types — there is no separate escrow ledger column, so `sp_release_escrow` logs a zero-amount audit entry rather than moving funds anywhere.
- `wallet_audit_logs` is append-only by convention, not by enforced permissions (no `REVOKE UPDATE/DELETE`), so it isn't literally immutable at the database level.
- The 7-day moving average in `vw_vehicle_revenue_moving_avg` uses a **row-based** window (`ROWS BETWEEN 6 PRECEDING AND CURRENT ROW`) over each vehicle's daily-revenue rows. If a vehicle has a day with zero completed trips, that date is skipped entirely, so the window can span more than 7 calendar days for vehicles with gaps.
- `postgres_seeder.py` / `mongo_seeder.py` contain hardcoded local credentials — replace before using against anything but a local dev database.

\echo '===  Vehicle lookup by license plate (tests unique constraint index) ==='
\echo '--- Result ---'
SELECT * FROM vehicles
WHERE license_plate = (SELECT license_plate FROM vehicles ORDER BY random() LIMIT 1);

\echo '--- Plan ---'
EXPLAIN ANALYZE
SELECT * FROM vehicles
WHERE license_plate = (SELECT license_plate FROM vehicles ORDER BY random() LIMIT 1);


\echo '===  Wallet audit history for one rider, most recent first ==='
\echo '--- Result ---'
SELECT * FROM wallet_audit_logs
WHERE rider_id = (SELECT id FROM riders ORDER BY random() LIMIT 1)
ORDER BY "timestamp" DESC
LIMIT 20;

\echo '--- Plan ---'
EXPLAIN ANALYZE
SELECT * FROM wallet_audit_logs
WHERE rider_id = (SELECT id FROM riders ORDER BY random() LIMIT 1)
ORDER BY "timestamp" DESC
LIMIT 20;


\echo '===  Trips joined with vehicles, filtered by date range and status ==='
\echo '--- Result ---'
SELECT t.id, t.fare_amount, t.created_at, v.class, v.license_plate
FROM trips t
JOIN vehicles v ON v.id = t.vehicle_id
WHERE t.status = 'COMPLETED'
  AND t.created_at >= now() - interval '7 days' LIMIT 20;

\echo '--- Plan ---'
EXPLAIN ANALYZE
SELECT t.id, t.fare_amount, t.created_at, v.class, v.license_plate
FROM trips t
JOIN vehicles v ON v.id = t.vehicle_id
WHERE t.status = 'COMPLETED'
  AND t.created_at >= now() - interval '7 days';


\echo '===  Average fare grouped by vehicle class (aggregate over full trips table) ==='
\echo '--- Result ---'
SELECT v.class, round(avg(t.fare_amount), 2) AS avg_fare, count(*)
FROM trips t
JOIN vehicles v ON v.id = t.vehicle_id
GROUP BY v.class
ORDER BY avg_fare;

\echo '--- Plan ---'
EXPLAIN ANALYZE
SELECT v.class, round(avg(t.fare_amount), 2) AS avg_fare, count(*)
FROM trips t
JOIN vehicles v ON v.id = t.vehicle_id
GROUP BY v.class
ORDER BY avg_fare;


\echo '=== Top 10 vehicles by lifetime earnings (materialized view) ==='
\echo '--- Result ---'
SELECT * FROM mv_vehicle_lifetime_stats
ORDER BY lifetime_earnings DESC
LIMIT 10;

\echo '--- Plan ---'
EXPLAIN ANALYZE
SELECT * FROM mv_vehicle_lifetime_stats
ORDER BY lifetime_earnings DESC
LIMIT 10;


\echo '===  Revenue moving average + rank for one vehicle (window-function view) ==='
\echo '--- Result ---'
SELECT * FROM vw_vehicle_revenue_moving_avg
WHERE vehicle_id = (SELECT id FROM vehicles ORDER BY random() LIMIT 1)
ORDER BY revenue_date;

\echo '--- Plan ---'
EXPLAIN ANALYZE
SELECT * FROM vw_vehicle_revenue_moving_avg
WHERE vehicle_id = (SELECT id FROM vehicles ORDER BY random() LIMIT 1)
ORDER BY revenue_date;


\echo '=== Riders with a wallet balance above average (subquery + full scan comparison) ==='
\echo '--- Result ---'
SELECT id, name, wallet_balance FROM riders
WHERE wallet_balance > (SELECT avg(wallet_balance) FROM riders)
ORDER BY wallet_balance DESC
LIMIT 20;

\echo '--- Plan ---'
EXPLAIN ANALYZE
SELECT id, name, wallet_balance FROM riders
WHERE wallet_balance > (SELECT avg(wallet_balance) FROM riders)
ORDER BY wallet_balance DESC
LIMIT 20;
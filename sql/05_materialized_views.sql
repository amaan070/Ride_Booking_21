-- Remove the existing materialized view before recreating it.
DROP MATERIALIZED VIEW IF EXISTS mv_vehicle_lifetime_stats;

-- Create a materialized view containing lifetime statistics for each vehicle.
CREATE MATERIALIZED VIEW mv_vehicle_lifetime_stats AS
SELECT
    v.id AS vehicle_id,
    v.license_plate,
    v.class,
    v.is_active,

    -- Count all trips associated with each vehicle.
    COUNT(t.id) AS lifetime_trip_count,

    -- Sum fares only for completed trips; return 0 if there are none.
    COALESCE(SUM(t.fare_amount) FILTER (WHERE t.status = 'COMPLETED'), 0.00) AS lifetime_earnings
FROM vehicles v

-- Keep vehicles even if they have no trips.
LEFT JOIN trips t ON t.vehicle_id = v.id

-- Group trips to calculate statistics for each vehicle.
GROUP BY v.id, v.license_plate, v.class, v.is_active
WITH DATA;

-- Create a unique index required for concurrent materialized view refreshes.
CREATE UNIQUE INDEX idx_mv_vehicle_lifetime_stats_vehicle_id
    ON mv_vehicle_lifetime_stats (vehicle_id);

-- ---------------------------------------------------------------------
-- refresh_mv_vehicle_lifetime_stats
-- ---------------------------------------------------------------------

-- Function to refresh the materialized view without blocking readers.
CREATE OR REPLACE FUNCTION refresh_mv_vehicle_lifetime_stats()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Refresh the stored statistics concurrently.
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_vehicle_lifetime_stats;
END;
$$;
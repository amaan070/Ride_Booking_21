use("ridesync_mongo");

db.createCollection("VehicleMetadata");
db.createCollection("TripReviews");
db.createCollection("TelemetryPings");

// Geospatial index for finding nearby vehicles
db.TelemetryPings.createIndex({
    location: "2dsphere"
});

// TTL index: automatically delete telemetry data after 2 hours
db.TelemetryPings.createIndex(
    {
        created_at: 1
    },
    {
        expireAfterSeconds: 7200
    }
);

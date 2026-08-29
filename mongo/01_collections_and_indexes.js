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

// Sample vehicle metadata
db.VehicleMetadata.insertMany([
    {
        vehicle_id: "550e8400-e29b-41d4-a716-446655440001",
        inspection_records: [
            {
                inspection_date: new Date("2026-08-01"),
                result: "PASSED",
                notes: "Vehicle inspection completed successfully"
            }
        ],
        features: {
            air_conditioning: true,
            gps: true,
            dashcam: true
        },
        created_at: new Date()
    },
    {
        vehicle_id: "550e8400-e29b-41d4-a716-446655440002",
        inspection_records: [
            {
                inspection_date: new Date("2026-08-10"),
                result: "PASSED",
                notes: "All systems functioning normally"
            }
        ],
        features: {
            air_conditioning: true,
            gps: true,
            dashcam: false
        },
        created_at: new Date()
    }
]);

// Sample trip reviews
db.TripReviews.insertMany([
    {
        trip_id: "660e8400-e29b-41d4-a716-446655440001",
        vehicle_id: "550e8400-e29b-41d4-a716-446655440001",
        rating: 5,
        feedback_tags: [
            "CLEAN_VEHICLE",
            "FRIENDLY_DRIVER"
        ],
        created_at: new Date()
    },
    {
        trip_id: "660e8400-e29b-41d4-a716-446655440002",
        vehicle_id: "550e8400-e29b-41d4-a716-446655440002",
        rating: 4,
        feedback_tags: [
            "SAFE_DRIVING",
            "ON_TIME"
        ],
        created_at: new Date()
    },
    {
        trip_id: "660e8400-e29b-41d4-a716-446655440003",
        vehicle_id: "550e8400-e29b-41d4-a716-446655440001",
        rating: 5,
        feedback_tags: [
            "FRIENDLY_DRIVER",
            "COMFORTABLE_RIDE"
        ],
        created_at: new Date()
    }
]);

// Sample telemetry pings
db.TelemetryPings.insertMany([
    {
        vehicle_id: "550e8400-e29b-41d4-a716-446655440001",
        is_available: true,
        location: {
            type: "Point",
            coordinates: [77.5946, 12.9716]
        },
        created_at: new Date()
    },
    {
        vehicle_id: "550e8400-e29b-41d4-a716-446655440002",
        is_available: true,
        location: {
            type: "Point",
            coordinates: [77.6000, 12.9750]
        },
        created_at: new Date()
    },
    {
        vehicle_id: "550e8400-e29b-41d4-a716-446655440003",
        is_available: false,
        location: {
            type: "Point",
            coordinates: [77.6100, 12.9800]
        },
        created_at: new Date()
    }
]);
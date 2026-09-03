use("ridesync_mongo");

const results = {};

// 1. $geoNear - nearest available vehicle within 5km
results.geoNear_nearest_vehicle = db.TelemetryPings.aggregate([
    {
        $geoNear: {
            near: { type: "Point", coordinates: [78.4867, 17.3850] },
            distanceField: "distance_meters",
            maxDistance: 5000,
            query: { is_available: true },
            spherical: true
        }
    },
    { $limit: 1 }
], { explain: true });

// 2. Find all pings for one vehicle
results.pings_by_vehicle = db.TelemetryPings.find(
    { vehicle_id: db.TelemetryPings.findOne().vehicle_id }
).explain("executionStats");

// 3. Count available vehicles right now (tests is_available filter, no index)
results.count_available = db.TelemetryPings.find(
    { is_available: true }
).explain("executionStats");

// 4. Geospatial + availability combined filter
results.geo_plus_availability = db.TelemetryPings.find({
    location: {
        $near: {
            $geometry: { type: "Point", coordinates: [78.4867, 17.3850] },
            $maxDistance: 3000
        }
    },
    is_available: true
}).explain("executionStats");

// 5. Reviews for one vehicle 
results.reviews_by_vehicle = db.TripReviews.find(
    { vehicle_id: db.TripReviews.findOne().vehicle_id }
).explain("executionStats");

// 6. Reviews with rating >= 4 
results.high_rated_reviews = db.TripReviews.find(
    { rating: { $gte: 4 } }
).explain("executionStats");

// 7. $facet review analysis 
results.facet_review_analysis = db.TripReviews.aggregate([
    {
        $facet: {
            ratingStats: [{ $group: { _id: "$rating", count: { $sum: 1 } } }],
            topTags: [
                { $unwind: "$feedback_tags" },
                { $group: { _id: "$feedback_tags", count: { $sum: 1 } } },
                { $sort: { count: -1 } },
                { $limit: 10 }
            ]
        }
    }
], { explain: true });

// 8. VehicleMetadata lookup by vehicle_id 
results.vehicle_metadata_lookup = db.VehicleMetadata.find(
    { vehicle_id: db.VehicleMetadata.findOne().vehicle_id }
).explain("executionStats");

printjson(results);
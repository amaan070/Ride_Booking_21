use("ridesync_mongo");

// Sample rider location: Bengaluru
const rider_location = {
    type: "Point",
    coordinates: [77.5946, 12.9716]
};

const nearest_vehicle = db.TelemetryPings.aggregate([
    {
        $geoNear: {
            near: rider_location,
            key: "location",
            distanceField: "distance_meters",
            maxDistance: 5000,
            spherical: true,
            query: {
                is_available: true
            }
        }
    },
    {
        $limit: 1
    }
]);

const result = nearest_vehicle.toArray();

if (result.length > 0) {
    print("Nearest available vehicle within 5 km:");
    printjson(result[0]);
} else {
    print("No available vehicle found within 5 km.");
}
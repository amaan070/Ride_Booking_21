// Select database
const db = db.getSiblingDB("ridesync_mongo");


export function findNearestVehicle(
    longitude,
    latitude,
    maxDistanceMeters = 5000
) {
    const rider_location = {
        type: "Point",
        coordinates: [longitude, latitude]
    };

    const result = db.TelemetryPings.aggregate([
        {
            $geoNear: {
                near: rider_location,
                key: "location",
                distanceField: "distance_meters",
                maxDistance: maxDistanceMeters,
                spherical: true,
                query: {
                    is_available: true
                }
            }
        },
        {
            $limit: 1
        }
    ]).toArray();

    return result.length > 0 ? result[0] : null;
}

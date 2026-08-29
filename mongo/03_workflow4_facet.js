use("ridesync_mongo");

// ============================================================
// Workflow 4: Review Analysis using $facet and $unwind
// Runs two separate analyses in a single query:
//   1. Rating distribution + average rating (per vehicle class of review)
//   2. Most common feedback tags (using $unwind to flatten the array)
// ============================================================

const result = db.TripReviews.aggregate([
    {
        $facet: {
            // ---- Facet 1: Rating distribution + average rating ----
            ratingStats: [
                {
                    $group: {
                        _id: "$rating",
                        count: { $sum: 1 }
                    }
                },
                { $sort: { _id: 1 } }
            ],

            averageRating: [
                {
                    $group: {
                        _id: null,
                        avgRating: { $avg: "$rating" },
                        totalReviews: { $sum: 1 }
                    }
                },
                { $project: { _id: 0, avgRating: { $round: ["$avgRating", 2] }, totalReviews: 1 } }
            ],

            // ---- Facet 2: Most common feedback tags ----
            topFeedbackTags: [
                // $unwind flattens the feedback_tags array so each tag
                // becomes its own document we can group on individually
                { $unwind: "$feedback_tags" },
                {
                    $group: {
                        _id: "$feedback_tags",
                        count: { $sum: 1 }
                    }
                },
                { $sort: { count: -1 } },
                { $limit: 10 }
            ]
        }
    }
]).toArray();

printjson(result);
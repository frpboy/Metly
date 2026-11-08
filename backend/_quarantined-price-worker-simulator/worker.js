export default {
    async fetch(req, env, ctx) {
        // CORS
        const cors = {
            "access-control-allow-origin": "*",
            "access-control-allow-headers": "content-type",
            "access-control-allow-methods": "GET,OPTIONS",
        };

        if (req.method === "OPTIONS") {
            return new Response(null, { headers: cors });
        }

        // Simulate fetching real data (replace this with real API calls later)
        // Caching logic would go here (using Cache API or KV)

        // Gold: ~60,000 INR/10g
        // Silver: ~75,000 INR/kg

        // Random jitter for simulation
        const jitter = () => (Math.random() - 0.5) * 0.005;

        const goldPrice = 132760 * (1 + jitter());
        const silverPrice = 170000 * (1 + jitter());

        const data = {
            gold: {
                metal: "gold",
                price: Math.round(goldPrice),
                unit: "INR/10g",
                recentHigh: 136500,
                updatedAt: new Date().toISOString(),
            },
            silver: {
                metal: "silver",
                price: Math.round(silverPrice),
                unit: "INR/kg",
                recentHigh: 190000,
                updatedAt: new Date().toISOString(),
            }
        };

        return new Response(JSON.stringify(data), {
            headers: {
                "content-type": "application/json",
                ...cors,
            },
        });
    },
};

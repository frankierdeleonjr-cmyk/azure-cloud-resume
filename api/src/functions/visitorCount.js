const { app } = require("@azure/functions");
const { TableClient } = require("@azure/data-tables");

const tableName = "VisitorCounts";
const partitionKey = "portfolio";
const rowKey = "site";

function getTableClient() {
    const connectionString = process.env.AzureWebJobsStorage;

    if (!connectionString) {
        throw new Error("AzureWebJobsStorage is not configured.");
    }

    return TableClient.fromConnectionString(connectionString, tableName);
}

app.http("visitorCount", {
    methods: ["GET"],
    authLevel: "anonymous",
    route: "visitors",
    handler: async (request, context) => {
        context.log("Visitor counter API endpoint requested.");

        try {
            const tableClient = getTableClient();

            await tableClient.createTable();

            let count = 1;

            try {
                const visitorEntity = await tableClient.getEntity(partitionKey, rowKey);

                count = Number(visitorEntity.count || 0) + 1;

                await tableClient.updateEntity(
                    {
                        partitionKey,
                        rowKey,
                        count
                    },
                    "Merge"
                );
            } catch (error) {
                if (error.statusCode === 404) {
                    await tableClient.createEntity({
                        partitionKey,
                        rowKey,
                        count
                    });
                } else {
                    throw error;
                }
            }

            return {
                status: 200,
                jsonBody: {
                    count
                }
            };
        } catch (error) {
            context.error("Visitor counter request failed.", error);

            return {
                status: 500,
                jsonBody: {
                    message: "Visitor counter unavailable."
                }
            };
        }
    }
});
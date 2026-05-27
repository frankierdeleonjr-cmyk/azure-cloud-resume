const { app } = require("@azure/functions");
const { TableClient } = require("@azure/data-tables");
const { ManagedIdentityCredential } = require("@azure/identity");

const tableName = "VisitorCounts";
const partitionKey = "portfolio";
const rowKey = "site";
const maxUpdateAttempts = 5;

function getTableClient() {
    const tableStorageEndpoint = process.env.TABLE_STORAGE_ENDPOINT;

    if (tableStorageEndpoint) {
        const managedIdentityClientId = process.env.AZURE_CLIENT_ID;

        if (!managedIdentityClientId) {
            throw new Error("AZURE_CLIENT_ID is not configured for managed identity authentication.");
        }

        const credential = new ManagedIdentityCredential(managedIdentityClientId);

        return new TableClient(tableStorageEndpoint, tableName, credential);
    }

    const localConnectionString = process.env.AzureWebJobsStorage;

    if (!localConnectionString) {
        throw new Error("Local AzureWebJobsStorage is not configured.");
    }

    return TableClient.fromConnectionString(localConnectionString, tableName);
}

async function incrementVisitorCount(tableClient) {
    await tableClient.createTable();

    for (let attempt = 1; attempt <= maxUpdateAttempts; attempt += 1) {
        try {
            const visitorEntity = await tableClient.getEntity(partitionKey, rowKey);
            const updatedCount = Number(visitorEntity.count || 0) + 1;

            await tableClient.updateEntity(
                {
                    partitionKey,
                    rowKey,
                    count: updatedCount
                },
                "Merge",
                {
                    etag: visitorEntity.etag
                }
            );

            return updatedCount;
        } catch (error) {
            if (error.statusCode === 404) {
                try {
                    await tableClient.createEntity({
                        partitionKey,
                        rowKey,
                        count: 1
                    });

                    return 1;
                } catch (createError) {
                    if (createError.statusCode === 409) {
                        continue;
                    }

                    throw createError;
                }
            }

            if (error.statusCode === 412) {
                continue;
            }

            throw error;
        }
    }

    throw new Error("Visitor counter update failed after multiple concurrent update attempts.");
}

app.http("visitorCount", {
    methods: ["GET"],
    authLevel: "anonymous",
    route: "visitors",
    handler: async (request, context) => {
        context.log("Visitor counter API endpoint requested.");

        try {
            const tableClient = getTableClient();
            const count = await incrementVisitorCount(tableClient);

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
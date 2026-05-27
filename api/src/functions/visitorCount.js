document.addEventListener("DOMContentLoaded", async () => {
    const visitorCountElement = document.getElementById("visitor-count");

    if (!visitorCountElement) {
        return;
    }

    const browserIdStorageKey = "azureCloudResumeBrowserId";
    const visitorApiUrl =
        "https://func-azure-cloud-resume-frd2026.azurewebsites.net/api/visitors";

    function getOrCreateBrowserId() {
        let browserId = window.localStorage.getItem(browserIdStorageKey);

        if (!browserId) {
            browserId = window.crypto.randomUUID();
            window.localStorage.setItem(browserIdStorageKey, browserId);
        }

        return browserId;
    }

    try {
        const browserId = getOrCreateBrowserId();

        const response = await fetch(visitorApiUrl, {
            method: "POST",
            headers: {
                "Content-Type": "application/json"
            },
            body: JSON.stringify({
                browserId
            })
        });

        if (!response.ok) {
            throw new Error(
                `Visitor API request failed with status ${response.status}.`
            );
        }

        const data = await response.json();

        if (typeof data.count !== "number") {
            throw new Error("Visitor API returned an invalid count.");
        }

        visitorCountElement.textContent = data.count.toLocaleString();
    } catch (error) {
        console.error("Unable to load visitor count:", error);
        visitorCountElement.textContent = "Unavailable";
    }
});
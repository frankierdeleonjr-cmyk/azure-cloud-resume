document.addEventListener("DOMContentLoaded", async () => {
    const visitorCountElement = document.getElementById("visitor-count");

    if (!visitorCountElement) {
        return;
    }

    try {
        const response = await fetch(
            "https://func-azure-cloud-resume-frd2026.azurewebsites.net/api/visitors"
        );

        if (!response.ok) {
            throw new Error(`Visitor API request failed with status ${response.status}.`);
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
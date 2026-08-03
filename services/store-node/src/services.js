const catalogBaseUrl = process.env.CATALOG_SERVICE_URL || "http://localhost:8080";
const insightsBaseUrl = process.env.INSIGHTS_SERVICE_URL || "http://localhost:8000";

async function fetchJson(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Request failed ${response.status}: ${url}`);
  }
  return response.json();
}

export function getCatalogUrl() {
  return catalogBaseUrl;
}

export async function getCategories() {
  return fetchJson(`${catalogBaseUrl}/categories`);
}

export async function getPrompts({ categoryId, q } = {}) {
  const url = new URL(`${catalogBaseUrl}/prompts`);
  if (categoryId) url.searchParams.set("categoryId", categoryId);
  if (q) url.searchParams.set("q", q);
  return fetchJson(url);
}

export async function getPrompt(id) {
  return fetchJson(`${catalogBaseUrl}/prompts/${id}`);
}

export async function getRecommendations(promptId) {
  return fetchJson(`${insightsBaseUrl}/recommendations?promptId=${encodeURIComponent(promptId)}`);
}

export async function getPopular() {
  return fetchJson(`${insightsBaseUrl}/stats/popular`);
}

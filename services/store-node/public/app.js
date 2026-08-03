const state = {
  categories: [],
  prompts: [],
  cart: new Map(),
  selectedPrompt: null
};

const currency = new Intl.NumberFormat("pt-BR", {
  style: "currency",
  currency: "BRL"
});

const elements = {
  category: document.querySelector("#category"),
  filters: document.querySelector("#filters"),
  search: document.querySelector("#search"),
  promptGrid: document.querySelector("#promptGrid"),
  resultCount: document.querySelector("#resultCount"),
  detailPanel: document.querySelector("#detailPanel"),
  cartItems: document.querySelector("#cartItems"),
  cartTotal: document.querySelector("#cartTotal"),
  cartCount: document.querySelector("#cartCount"),
  clearCart: document.querySelector("#clearCart"),
  checkoutForm: document.querySelector("#checkoutForm"),
  checkoutStatus: document.querySelector("#checkoutStatus"),
  cardTemplate: document.querySelector("#promptCardTemplate")
};

function formatPrice(cents) {
  return currency.format(cents / 100);
}

function tagList(tags) {
  return tags.slice(0, 3).map((tag) => `<span class="tag">${tag}</span>`).join("");
}

async function api(path, options) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({}));
    throw new Error(body.error || `Falha HTTP ${response.status}`);
  }
  return response.json();
}

function renderCategories() {
  elements.category.innerHTML = `<option value="">Todas</option>`;
  for (const category of state.categories) {
    const option = document.createElement("option");
    option.value = category.id;
    option.textContent = category.name;
    elements.category.append(option);
  }
}

function renderPrompts() {
  elements.promptGrid.innerHTML = "";
  elements.resultCount.textContent = `${state.prompts.length} prompt${state.prompts.length === 1 ? "" : "s"}`;

  for (const prompt of state.prompts) {
    const fragment = elements.cardTemplate.content.cloneNode(true);
    const card = fragment.querySelector(".prompt-card");
    card.querySelector(".category").textContent = prompt.categoryName;
    card.querySelector(".price").textContent = formatPrice(prompt.priceCents);
    card.querySelector("h3").textContent = prompt.title;
    card.querySelector("p").textContent = prompt.description;
    card.querySelector(".tags").innerHTML = tagList(prompt.tags);
    card.querySelector(".details").addEventListener("click", () => selectPrompt(prompt.id));
    card.querySelector(".add").addEventListener("click", () => addToCart(prompt));
    elements.promptGrid.append(fragment);
  }
}

async function selectPrompt(id) {
  elements.detailPanel.innerHTML = `<p class="muted">Carregando detalhes...</p>`;
  const { prompt, recommendations } = await api(`/api/prompts/${id}`);
  state.selectedPrompt = prompt;

  elements.detailPanel.innerHTML = `
    <span class="category">${prompt.categoryName}</span>
    <h2>${prompt.title}</h2>
    <p class="muted">${prompt.description}</p>
    <div class="prompt-text">${prompt.promptText}</div>
    <div class="card-top">
      <strong>${formatPrice(prompt.priceCents)}</strong>
      <button class="add" type="button" id="detailAdd">Adicionar</button>
    </div>
    <h2 style="margin-top:18px">Recomendações</h2>
    <div class="recommendations">
      ${recommendations.length ? recommendations.map((item) => `
        <button class="recommendation" type="button" data-id="${item.id}">
          <strong>${item.title}</strong>
          <span>${item.category_name || item.categoryName} · ${formatPrice(item.price_cents || item.priceCents)}</span>
        </button>
      `).join("") : `<p class="muted">Sem recomendações disponíveis agora.</p>`}
    </div>
  `;
  document.querySelector("#detailAdd").addEventListener("click", () => addToCart(prompt));
  elements.detailPanel.querySelectorAll(".recommendation").forEach((button) => {
    button.addEventListener("click", () => selectPrompt(button.dataset.id));
  });
}

function addToCart(prompt) {
  const current = state.cart.get(prompt.id) || { ...prompt, quantity: 0 };
  current.quantity += 1;
  state.cart.set(prompt.id, current);
  renderCart();
}

function removeFromCart(id) {
  state.cart.delete(Number(id));
  renderCart();
}

function renderCart() {
  const items = [...state.cart.values()];
  elements.cartCount.textContent = items.reduce((count, item) => count + item.quantity, 0);
  elements.cartItems.innerHTML = items.length ? "" : `<p class="muted">Carrinho vazio.</p>`;

  let total = 0;
  for (const item of items) {
    total += item.priceCents * item.quantity;
    const row = document.createElement("div");
    row.className = "cart-item";
    row.innerHTML = `
      <div>
        <strong>${item.title}</strong>
        <div class="muted">${item.quantity} x ${formatPrice(item.priceCents)}</div>
      </div>
      <button type="button" aria-label="Remover ${item.title}" data-id="${item.id}">×</button>
    `;
    row.querySelector("button").addEventListener("click", () => removeFromCart(item.id));
    elements.cartItems.append(row);
  }

  elements.cartTotal.textContent = formatPrice(total);
}

async function loadPrompts() {
  const params = new URLSearchParams();
  if (elements.category.value) params.set("categoryId", elements.category.value);
  if (elements.search.value.trim()) params.set("q", elements.search.value.trim());
  state.prompts = await api(`/api/prompts?${params}`);
  renderPrompts();
}

async function bootstrap() {
  const data = await api("/api/bootstrap");
  state.categories = data.categories;
  state.prompts = data.prompts;
  renderCategories();
  renderPrompts();
  renderCart();
}

elements.filters.addEventListener("submit", async (event) => {
  event.preventDefault();
  await loadPrompts();
});

elements.clearCart.addEventListener("click", () => {
  state.cart.clear();
  renderCart();
});

elements.checkoutForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  elements.checkoutStatus.textContent = "";
  const items = [...state.cart.values()].map((item) => ({ id: item.id, quantity: item.quantity }));
  try {
    const order = await api("/api/checkout", {
      method: "POST",
      body: JSON.stringify({
        buyerName: new FormData(elements.checkoutForm).get("buyerName"),
        buyerEmail: new FormData(elements.checkoutForm).get("buyerEmail"),
        items
      })
    });
    state.cart.clear();
    renderCart();
    elements.checkoutForm.reset();
    elements.checkoutStatus.textContent = `Pedido ${order.id.slice(0, 8)} criado: ${formatPrice(order.totalCents)}.`;
  } catch (error) {
    elements.checkoutStatus.textContent = error.message;
  }
});

bootstrap().catch((error) => {
  elements.promptGrid.innerHTML = `<p class="muted">Nao foi possivel carregar a vitrine: ${error.message}</p>`;
});

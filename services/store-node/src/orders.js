import { randomUUID } from "node:crypto";

import { pool } from "./db.js";

export async function createOrder({ buyerName, buyerEmail, items }) {
  if (!items.length) {
    const error = new Error("Cart is empty");
    error.status = 400;
    throw error;
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");

    const ids = items.map((item) => item.id);
    const { rows: prompts } = await client.query(
      "SELECT id, title, price_cents FROM prompts WHERE active = true AND id = ANY($1::int[])",
      [ids]
    );
    if (prompts.length !== ids.length) {
      const error = new Error("One or more prompts are unavailable");
      error.status = 409;
      throw error;
    }

    const promptById = new Map(prompts.map((prompt) => [prompt.id, prompt]));
    const totalCents = items.reduce((total, item) => {
      const prompt = promptById.get(item.id);
      return total + prompt.price_cents * item.quantity;
    }, 0);
    const orderId = randomUUID();

    await client.query(
      "INSERT INTO orders (id, buyer_name, buyer_email, total_cents, status) VALUES ($1, $2, $3, $4, $5)",
      [orderId, buyerName, buyerEmail, totalCents, "paid_simulated"]
    );

    for (const item of items) {
      const prompt = promptById.get(item.id);
      await client.query(
        "INSERT INTO order_items (order_id, prompt_id, quantity, unit_price_cents) VALUES ($1, $2, $3, $4)",
        [orderId, item.id, item.quantity, prompt.price_cents]
      );
      await client.query(
        "INSERT INTO prompt_events (prompt_id, event_type, source) VALUES ($1, 'purchase', 'store-node')",
        [item.id]
      );
    }

    await client.query("COMMIT");
    return {
      id: orderId,
      buyerName,
      buyerEmail,
      totalCents,
      status: "paid_simulated",
      items: prompts.map((prompt) => ({
        id: prompt.id,
        title: prompt.title,
        priceCents: prompt.price_cents,
        quantity: items.find((item) => item.id === prompt.id)?.quantity || 1
      }))
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function recordView(promptId) {
  await pool.query(
    "INSERT INTO prompt_events (prompt_id, event_type, source) VALUES ($1, 'view', 'store-node')",
    [promptId]
  );
}

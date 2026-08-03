import express from "express";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { httpLogger, logger, logException } from "./logging.js";
import { createOrder, recordView } from "./orders.js";
import { getCategories, getPopular, getPrompt, getPrompts, getRecommendations } from "./services.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export function createApp() {
  const app = express();

  app.use(httpLogger);
  app.use(express.json());
  app.use(express.static(path.join(__dirname, "..", "public"), {
    etag: true,
    maxAge: process.env.NODE_ENV === "production" ? "1h" : 0
  }));

  app.get("/health", (_req, res) => {
    res.json({ status: "ok", service: "store-node" });
  });

  app.get("/lab/status/:code", (req, res, next) => {
    if (process.env.LAB_MODE !== "true") {
      return next();
    }

    const code = Number(req.params.code);
    if (code === 400) {
      return res.status(400).json({ error: "Synthetic lab bad request" });
    }
    if (code === 500) {
      return next(new Error("Synthetic lab internal error"));
    }
    return res.status(400).json({ error: "Only status codes 400 and 500 are supported" });
  });

  app.get("/api/bootstrap", async (req, res, next) => {
    try {
      const [categories, prompts, popular] = await Promise.all([
        getCategories(),
        getPrompts({ categoryId: req.query.categoryId, q: req.query.q }),
        getPopular().catch(() => [])
      ]);
      res.json({ categories, prompts, popular });
    } catch (error) {
      next(error);
    }
  });

  app.get("/api/prompts", async (req, res, next) => {
    try {
      res.json(await getPrompts({ categoryId: req.query.categoryId, q: req.query.q }));
    } catch (error) {
      next(error);
    }
  });

  app.get("/api/prompts/:id", async (req, res, next) => {
    try {
      const id = Number(req.params.id);
      const [prompt, recommendations] = await Promise.all([
        getPrompt(id),
        getRecommendations(id).catch(() => [])
      ]);
      recordView(id).catch(() => undefined);
      res.json({ prompt, recommendations });
    } catch (error) {
      next(error);
    }
  });

  app.post("/api/checkout", async (req, res, next) => {
    try {
      const { buyerName, buyerEmail, items } = req.body;
      if (!buyerName || !buyerEmail || !Array.isArray(items)) {
        return res.status(400).json({ error: "buyerName, buyerEmail and items are required" });
      }
      const normalizedItems = items.map((item) => ({
        id: Number(item.id),
        quantity: Math.max(1, Number(item.quantity || 1))
      })).filter((item) => Number.isInteger(item.id) && item.id > 0);
      const order = await createOrder({ buyerName, buyerEmail, items: normalizedItems });
      res.status(201).json(order);
    } catch (error) {
      next(error);
    }
  });

  app.use((error, req, res, _next) => {
    const status = error.status || (error.message?.includes("not found") ? 404 : 500);
    res.locals.promptlabError = error;
    logException(logger, error, {
      method: req.method,
      path: req.path,
      status
    });
    res.status(status).json({
      error: status === 500 ? "Internal service error" : error.message
    });
  });

  return app;
}

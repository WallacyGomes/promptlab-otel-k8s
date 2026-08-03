import pg from "pg";

import { logger } from "./logging.js";

const { Pool } = pg;

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL || "postgresql://prompt_user:prompt_pass@localhost:5432/prompt_lab",
  max: 8,
  idleTimeoutMillis: 10_000
});

pool.on("error", (error) => {
  logger.error({
    "event.name": "database.pool.error",
    "error.type": error.name,
    "error.message": error.message,
    "exception.stacktrace": error.stack
  }, "database.pool.error");
});

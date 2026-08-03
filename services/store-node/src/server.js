import { createApp } from "./app.js";
import { logger } from "./logging.js";

const port = Number(process.env.PORT || 3000);

createApp().listen(port, "0.0.0.0", () => {
  logger.info({ "event.name": "service.started", port }, "service.started");
});

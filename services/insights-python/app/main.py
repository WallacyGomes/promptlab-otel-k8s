import logging
import os
import time

from fastapi import FastAPI, HTTPException, Query
from starlette.requests import Request
from starlette.responses import PlainTextResponse

from app.db import get_connection
from app.logging_config import configure_logging, log_exception, log_http_request
from app.models import PopularPrompt, PromptInsight

configure_logging()
logger = logging.getLogger("promptlab.insights")

app = FastAPI(title="PromptLab Insights", version="1.0.0")


@app.middleware("http")
async def log_request(request: Request, call_next):
    started_at = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception as error:
        duration_ms = (time.perf_counter() - started_at) * 1000
        log_http_request(logger, request.method, request.url.path, 500, duration_ms)
        log_exception(logger, error, request.method, request.url.path, 500)
        return PlainTextResponse("Internal Server Error", status_code=500)

    duration_ms = (time.perf_counter() - started_at) * 1000
    log_http_request(logger, request.method, request.url.path, response.status_code, duration_ms)
    return response


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "insights-python"}


@app.get("/lab/status/{status_code}")
def lab_status(status_code: int):
    if os.getenv("LAB_MODE", "false").lower() != "true":
        raise HTTPException(status_code=404, detail="Not found")
    if status_code == 400:
        raise HTTPException(status_code=400, detail="Synthetic lab bad request")
    if status_code == 500:
        raise RuntimeError("Synthetic lab internal error")
    raise HTTPException(
        status_code=400,
        detail="Only status codes 400 and 500 are supported",
    )


@app.get("/recommendations", response_model=list[PromptInsight])
def recommendations(promptId: int = Query(..., ge=1), limit: int = Query(4, ge=1, le=12)):
    with get_connection() as connection:
        source = connection.execute(
            """
            SELECT id, category_id, price_cents, tags
            FROM prompts
            WHERE id = %s AND active = true
            """,
            (promptId,),
        ).fetchone()
        if not source:
            raise HTTPException(status_code=404, detail="Prompt not found")

        rows = connection.execute(
            """
            SELECT p.id, p.category_id, c.name AS category_name, p.title, p.description,
                   p.price_cents, p.tags,
                   (
                     CASE WHEN p.category_id = %(category_id)s THEN 5 ELSE 0 END
                     + (SELECT count(*) FROM unnest(p.tags) tag WHERE tag = ANY(%(tags)s::text[]))
                     + GREATEST(0, 3 - abs(p.price_cents - %(price_cents)s) / 1000.0)
                     + COALESCE(e.purchases, 0) * 1.5
                     + COALESCE(e.views, 0) * 0.2
                   ) AS score
            FROM prompts p
            JOIN categories c ON c.id = p.category_id
            LEFT JOIN (
              SELECT prompt_id,
                     count(*) FILTER (WHERE event_type = 'view') AS views,
                     count(*) FILTER (WHERE event_type = 'purchase') AS purchases
              FROM prompt_events
              GROUP BY prompt_id
            ) e ON e.prompt_id = p.id
            WHERE p.active = true AND p.id <> %(prompt_id)s
            ORDER BY score DESC, p.created_at DESC
            LIMIT %(limit)s
            """,
            {
                "prompt_id": promptId,
                "category_id": source["category_id"],
                "price_cents": source["price_cents"],
                "tags": source["tags"],
                "limit": limit,
            },
        ).fetchall()
        return [PromptInsight(**row) for row in rows]


@app.get("/recommendations/category/{category_id}", response_model=list[PromptInsight])
def category_recommendations(category_id: int, limit: int = Query(6, ge=1, le=12)):
    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT p.id, p.category_id, c.name AS category_name, p.title, p.description,
                   p.price_cents, p.tags,
                   (COALESCE(e.purchases, 0) * 2 + COALESCE(e.views, 0) * 0.3) AS score
            FROM prompts p
            JOIN categories c ON c.id = p.category_id
            LEFT JOIN (
              SELECT prompt_id,
                     count(*) FILTER (WHERE event_type = 'view') AS views,
                     count(*) FILTER (WHERE event_type = 'purchase') AS purchases
              FROM prompt_events
              GROUP BY prompt_id
            ) e ON e.prompt_id = p.id
            WHERE p.active = true AND p.category_id = %s
            ORDER BY score DESC, p.created_at DESC
            LIMIT %s
            """,
            (category_id, limit),
        ).fetchall()
        return [PromptInsight(**row) for row in rows]


@app.get("/stats/popular", response_model=list[PopularPrompt])
def popular(limit: int = Query(8, ge=1, le=20)):
    with get_connection() as connection:
        rows = connection.execute(
            """
            SELECT p.id, p.title, c.name AS category_name,
                   count(pe.id) FILTER (WHERE pe.event_type = 'view')::int AS views,
                   count(pe.id) FILTER (WHERE pe.event_type = 'purchase')::int AS purchases,
                   (
                     count(pe.id) FILTER (WHERE pe.event_type = 'purchase') * 3
                     + count(pe.id) FILTER (WHERE pe.event_type = 'view')
                   )::float AS score
            FROM prompts p
            JOIN categories c ON c.id = p.category_id
            LEFT JOIN prompt_events pe ON pe.prompt_id = p.id
            WHERE p.active = true
            GROUP BY p.id, p.title, c.name
            ORDER BY score DESC, p.created_at DESC
            LIMIT %s
            """,
            (limit,),
        ).fetchall()
        return [PopularPrompt(**row) for row in rows]

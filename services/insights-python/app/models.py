from pydantic import BaseModel


class PromptInsight(BaseModel):
    id: int
    category_id: int
    category_name: str
    title: str
    description: str
    price_cents: int
    tags: list[str]
    score: float = 0


class PopularPrompt(BaseModel):
    id: int
    title: str
    category_name: str
    views: int
    purchases: int
    score: float

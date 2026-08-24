"""Contratos de entrada e saída da API (Pydantic v2)."""

from datetime import UTC, datetime

from pydantic import BaseModel, ConfigDict, Field


class HealthResponse(BaseModel):
    status: str
    version: str


class TaskCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    title: str = Field(min_length=1, max_length=120)
    description: str = Field(default="", max_length=1000)
    priority: int = Field(default=3, ge=1, le=5)


class TaskUpdate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    title: str | None = Field(default=None, min_length=1, max_length=120)
    description: str | None = Field(default=None, max_length=1000)
    priority: int | None = Field(default=None, ge=1, le=5)
    completed: bool | None = None


class TaskResponse(BaseModel):
    id: int
    title: str
    description: str
    priority: int
    completed: bool
    created_at: datetime


def utc_now() -> datetime:
    return datetime.now(UTC)

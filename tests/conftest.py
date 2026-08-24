"""Fixtures compartilhadas pela suíte de testes."""

import pytest
from fastapi.testclient import TestClient

from app.main import app, repository


@pytest.fixture()
def client() -> TestClient:
    """Cliente HTTP com o repositório limpo a cada teste (isolamento)."""
    repository.clear()
    with TestClient(app) as test_client:
        yield test_client
    repository.clear()


@pytest.fixture()
def sample_task(client: TestClient) -> dict:
    response = client.post(
        "/tasks",
        json={
            "title": "Configurar pipeline",
            "description": "GitHub Actions",
            "priority": 1,
        },
    )
    return response.json()

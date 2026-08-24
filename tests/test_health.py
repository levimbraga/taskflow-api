"""Testes de fumaça - executados também após o deploy na EC2."""

from app import __version__


def test_health_retorna_ok(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": __version__}


def test_documentacao_openapi_disponivel(client):
    assert client.get("/openapi.json").status_code == 200

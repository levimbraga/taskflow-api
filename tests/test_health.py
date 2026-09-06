"""Testes de fumaça - executados também após o deploy na EC2."""

from app import __version__


def test_health_retorna_ok(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "version": __version__}


def test_documentacao_openapi_disponivel(client):
    assert client.get("/openapi.json").status_code == 200


def test_endpoint_de_metricas_expoe_formato_prometheus(client):
    client.get("/health")  # gera ao menos uma amostra

    response = client.get("/metrics")

    assert response.status_code == 200
    assert "text/plain" in response.headers["content-type"]
    assert "http_requests_total" in response.text


def test_metricas_registram_a_rota_chamada(client):
    client.get("/tasks")

    corpo = client.get("/metrics").text

    assert "/tasks" in corpo

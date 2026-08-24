"""Testes de integração das rotas HTTP."""

import pytest


def test_criar_tarefa_retorna_201_e_corpo_completo(client):
    response = client.post(
        "/tasks",
        json={"title": "Escrever Terraform", "description": "VPC + EC2", "priority": 2},
    )

    assert response.status_code == 201
    body = response.json()
    assert body["id"] == 1
    assert body["title"] == "Escrever Terraform"
    assert body["completed"] is False
    assert body["created_at"]


def test_listar_tarefas_ordena_por_prioridade(client):
    client.post("/tasks", json={"title": "Baixa", "priority": 5})
    client.post("/tasks", json={"title": "Alta", "priority": 1})

    titulos = [item["title"] for item in client.get("/tasks").json()]

    assert titulos == ["Alta", "Baixa"]


def test_listar_com_filtro_de_concluidas(client, sample_task):
    client.patch(f"/tasks/{sample_task['id']}", json={"completed": True})
    client.post("/tasks", json={"title": "Pendente"})

    concluidas = client.get("/tasks", params={"completed": True}).json()
    pendentes = client.get("/tasks", params={"completed": False}).json()

    assert len(concluidas) == 1
    assert len(pendentes) == 1


def test_buscar_tarefa_inexistente_retorna_404(client):
    response = client.get("/tasks/999")

    assert response.status_code == 404
    assert "não encontrada" in response.json()["detail"]


def test_atualizar_tarefa_preserva_campos_nao_enviados(client, sample_task):
    response = client.patch(f"/tasks/{sample_task['id']}", json={"completed": True})

    body = response.json()
    assert body["completed"] is True
    assert body["title"] == sample_task["title"]
    assert body["priority"] == sample_task["priority"]


def test_remover_tarefa_retorna_204_e_some_da_listagem(client, sample_task):
    assert client.delete(f"/tasks/{sample_task['id']}").status_code == 204
    assert client.get("/tasks").json() == []


def test_remover_tarefa_inexistente_retorna_404(client):
    assert client.delete("/tasks/999").status_code == 404


@pytest.mark.parametrize(
    "payload",
    [
        {"title": ""},
        {"title": "x" * 121},
        {"title": "ok", "priority": 0},
        {"title": "ok", "priority": 6},
        {"description": "sem titulo"},
    ],
)
def test_payload_invalido_retorna_422(client, payload):
    assert client.post("/tasks", json=payload).status_code == 422

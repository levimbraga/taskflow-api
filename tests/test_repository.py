"""Testes unitários da camada de repositório."""

from app.repository import TaskRepository
from app.schemas import TaskCreate, TaskUpdate


def test_ids_sao_sequenciais():
    repo = TaskRepository()

    primeiro = repo.create(TaskCreate(title="A"))
    segundo = repo.create(TaskCreate(title="B"))

    assert (primeiro.id, segundo.id) == (1, 2)


def test_titulo_tem_espacos_removidos():
    repo = TaskRepository()

    task = repo.create(TaskCreate(title="  com espaços  "))

    assert task.title == "com espaços"


def test_update_em_id_inexistente_retorna_none():
    assert TaskRepository().update(42, TaskUpdate(completed=True)) is None


def test_delete_em_id_inexistente_retorna_false():
    assert TaskRepository().delete(42) is False


def test_clear_esvazia_o_repositorio():
    repo = TaskRepository()
    repo.create(TaskCreate(title="A"))

    repo.clear()

    assert repo.list() == []

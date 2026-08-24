"""Camada de persistência em memória.

Mantida propositalmente simples: o objetivo desta fase do projeto é a esteira de
CI/CD e a infraestrutura como código, não a modelagem de dados. A interface
abaixo é a mesma que um repositório com banco relacional exporia, o que permite
trocar a implementação em fases futuras sem alterar as rotas.
"""

from itertools import count

from app.schemas import TaskCreate, TaskResponse, TaskUpdate, utc_now


class TaskRepository:
    def __init__(self) -> None:
        self._items: dict[int, TaskResponse] = {}
        self._sequence = count(1)

    def create(self, payload: TaskCreate) -> TaskResponse:
        task = TaskResponse(
            id=next(self._sequence),
            title=payload.title,
            description=payload.description,
            priority=payload.priority,
            completed=False,
            created_at=utc_now(),
        )
        self._items[task.id] = task
        return task

    def get(self, task_id: int) -> TaskResponse | None:
        return self._items.get(task_id)

    def list(self, completed: bool | None = None) -> list[TaskResponse]:
        items = list(self._items.values())
        if completed is not None:
            items = [item for item in items if item.completed is completed]
        return sorted(items, key=lambda item: (item.priority, item.id))

    def update(self, task_id: int, payload: TaskUpdate) -> TaskResponse | None:
        current = self._items.get(task_id)
        if current is None:
            return None
        updated = current.model_copy(
            update=payload.model_dump(exclude_unset=True, exclude_none=True)
        )
        self._items[task_id] = updated
        return updated

    def delete(self, task_id: int) -> bool:
        return self._items.pop(task_id, None) is not None

    def clear(self) -> None:
        self._items.clear()

"""TaskFlow API - ponto de entrada da aplicação FastAPI."""

from fastapi import FastAPI, HTTPException, status

from app import __version__
from app.repository import TaskRepository
from app.schemas import HealthResponse, TaskCreate, TaskResponse, TaskUpdate

app = FastAPI(
    title="TaskFlow API",
    description="API REST de gerenciamento de tarefas - DevOps na Prática (PUCRS)",
    version=__version__,
)

repository = TaskRepository()


@app.get("/health", response_model=HealthResponse, tags=["infra"])
def health_check() -> HealthResponse:
    """Endpoint usado pelo health check do load balancer e pelos testes de fumaça."""
    return HealthResponse(status="ok", version=__version__)


@app.get("/tasks", response_model=list[TaskResponse], tags=["tasks"])
def list_tasks(completed: bool | None = None) -> list[TaskResponse]:
    """Lista todas as tarefas, opcionalmente filtrando por status de conclusão."""
    return repository.list(completed=completed)


@app.get("/tasks/{task_id}", response_model=TaskResponse, tags=["tasks"])
def get_task(task_id: int) -> TaskResponse:
    task = repository.get(task_id)
    if task is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Tarefa {task_id} não encontrada",
        )
    return task


@app.post(
    "/tasks",
    response_model=TaskResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["tasks"],
)
def create_task(payload: TaskCreate) -> TaskResponse:
    return repository.create(payload)


@app.patch("/tasks/{task_id}", response_model=TaskResponse, tags=["tasks"])
def update_task(task_id: int, payload: TaskUpdate) -> TaskResponse:
    task = repository.update(task_id, payload)
    if task is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Tarefa {task_id} não encontrada",
        )
    return task


@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["tasks"])
def delete_task(task_id: int) -> None:
    if not repository.delete(task_id):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Tarefa {task_id} não encontrada",
        )

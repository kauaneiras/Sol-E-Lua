"""Testes da API HTTP (pytest).

As regras do jogo são testadas em Prolog (prolog/test_solelua.pl). Aqui
conferimos só a "cola": rotas, formato do JSON e códigos de status.

Rodar: `uv run pytest` (na pasta backend) ou `make test-backend` (na raiz).
"""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)

# O mesmo puzzle de example_puzzle/3 em solelua.pl.
EXAMPLE = {
    "board": [
        [0, 0, 0, 1, 0, 0],
        [0, 0, 0, 0, 2, 2],
        [0, 2, 1, 0, 0, 0],
        [1, 0, 0, 0, 0, 0],
        [0, 0, 0, 1, 0, 2],
        [0, 0, 0, 0, 0, 0],
    ],
    "equal": [[4, 5, 5, 5], [5, 0, 5, 1]],
    "opposite": [[2, 2, 2, 3], [1, 1, 2, 1], [3, 2, 4, 2], [0, 3, 0, 4]],
}


def with_board(board):
    return {**EXAMPLE, "board": board}


def solved_example() -> list[list[int]]:
    return client.post("/api/solve", json=EXAMPLE).json()["board"]


def test_solve():
    response = client.post("/api/solve", json=EXAMPLE)
    assert response.status_code == 200
    assert response.json()["board"][0] == [2, 2, 1, 1, 2, 1]


def test_solve_without_solution():
    board = [row[:] for row in EXAMPLE["board"]]
    board[0][0:3] = [1, 1, 1]  # três sóis seguidos
    response = client.post("/api/solve", json=with_board(board))
    assert response.status_code == 422


def test_solve_rejects_malformed_board():
    response = client.post("/api/solve", json={"board": [[1, 2, 3]]})
    assert response.status_code == 422


def test_generate():
    response = client.post("/api/generate", json={"difficulty": "easy"})
    assert response.status_code == 200
    data = response.json()
    assert len(data["board"]) == 6 and all(len(row) == 6 for row in data["board"])
    assert 0 in sum(data["board"], [])
    assert len(data["equal"]) + len(data["opposite"]) > 0


def test_hint():
    response = client.post("/api/hint", json=EXAMPLE)
    assert response.status_code == 200
    hint = response.json()
    assert EXAMPLE["board"][hint["row"]][hint["col"]] == 0


def test_hint_on_complete_board():
    response = client.post("/api/hint", json=with_board(solved_example()))
    assert response.status_code == 422
    assert response.json()["detail"] == "O tabuleiro já está completo."


def test_hint_on_full_board_with_errors():
    board = solved_example()
    board[0][0], board[0][2] = board[0][2], board[0][0]  # troca lua e sol
    response = client.post("/api/hint", json=with_board(board))
    assert response.status_code == 422
    assert "não tem solução" in response.json()["detail"]

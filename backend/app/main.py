"""Rotas HTTP do Sol e Lua. Só valida o JSON e repassa para o Prolog.

    uv run fastapi dev app/main.py     (docs em http://localhost:8000/docs)
"""

from typing import Annotated, Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from app import prolog

app = FastAPI(title="Sol e Lua (Prolog + Elm)")

# 0 vazia, 1 sol, 2 lua; qualquer outra coisa o Pydantic recusa com 422.
Cell = Annotated[int, Field(ge=0, le=2)]
Row = Annotated[list[Cell], Field(min_length=6, max_length=6)]
Grid = Annotated[list[Row], Field(min_length=6, max_length=6)]

# Sinal: [linha1, coluna1, linha2, coluna2].
Coord = Annotated[int, Field(ge=0, le=5)]
Sign = Annotated[list[Coord], Field(min_length=4, max_length=4)]


class GenerateRequest(BaseModel):
    difficulty: Literal["easy", "medium", "hard"] = "medium"


class PuzzleRequest(BaseModel):
    board: Grid
    equal: list[Sign] = []
    opposite: list[Sign] = []


class PuzzleResponse(BaseModel):
    board: Grid
    equal: list[Sign]
    opposite: list[Sign]


class BoardResponse(BaseModel):
    board: Grid


class HintResponse(BaseModel):
    row: int
    col: int
    value: int


NO_SOLUTION = "Este tabuleiro não tem solução. Confira os símbolos colocados."
BOARD_COMPLETE = "O tabuleiro já está completo."


@app.post("/api/generate")
def generate(request: GenerateRequest) -> PuzzleResponse:
    board, equal, opposite = prolog.generate(request.difficulty)
    return PuzzleResponse(board=board, equal=equal, opposite=opposite)


@app.post("/api/solve")
def solve(request: PuzzleRequest) -> BoardResponse:
    try:
        return BoardResponse(board=prolog.solve(request.board, request.equal, request.opposite))
    except prolog.NoSolution:
        raise HTTPException(status_code=422, detail=NO_SOLUTION) from None


@app.post("/api/hint")
def hint(request: PuzzleRequest) -> HintResponse:
    try:
        row, col, value = prolog.hint(request.board, request.equal, request.opposite)
    except prolog.NoSolution:
        raise HTTPException(status_code=422, detail=NO_SOLUTION) from None
    except prolog.BoardComplete:
        raise HTTPException(status_code=422, detail=BOARD_COMPLETE) from None
    return HintResponse(row=row, col=col, value=value)

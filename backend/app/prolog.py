"""Chama os predicados de solelua.pl pelo janus (SWI-Prolog dentro do Python).

É o único arquivo que conhece o janus; main.py só usa as funções daqui.
"""

from pathlib import Path

import janus_swi as janus

Grid = list[list[int]]
Signs = list[list[int]]  # cada sinal: [linha1, coluna1, linha2, coluna2]

PROLOG_FILE = Path(__file__).parent.parent / "prolog" / "solelua.pl"

janus.consult(str(PROLOG_FILE))


class NoSolution(Exception):
    """O tabuleiro enviado não tem solução."""


class BoardComplete(Exception):
    """Não há casa vazia para dar dica."""


def solve(puzzle: Grid, equal: Signs, opposite: Signs) -> Grid:
    result = janus.query_once(
        "solelua:solve(Puzzle, Equal, Opposite, Solution)",
        {"Puzzle": puzzle, "Equal": equal, "Opposite": opposite},
    )
    if not result["truth"]:
        raise NoSolution
    return result["Solution"]


def generate(difficulty: str) -> tuple[Grid, Signs, Signs]:
    # String do Python chega como string no Prolog; generate/4 quer um átomo.
    result = janus.query_once(
        "atom_string(D, Name), solelua:generate(D, Puzzle, Equal, Opposite)",
        {"Name": difficulty},
    )
    return result["Puzzle"], result["Equal"], result["Opposite"]


def hint(board: Grid, equal: Signs, opposite: Signs) -> tuple[int, int, int]:
    result = janus.query_once(
        "solelua:hint(Board, Equal, Opposite, Result)",
        {"Board": board, "Equal": equal, "Opposite": opposite},
    )["Result"]
    match result:
        case "complete":
            raise BoardComplete
        case "unsolvable":
            raise NoSolution
        case [row, col, value]:
            return row, col, value
    raise ValueError(f"resultado inesperado de hint/4: {result!r}")

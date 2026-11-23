/*  test_solelua.pl: testes plunit do Sol e Lua.

    Para rodar:
        $ swipl -g run_tests -t halt backend/prolog/test_solelua.pl
*/

:- use_module(solelua).
:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(apply)).

:- begin_tests(solve).

test(example_puzzle, true(Row1 == [2,2,1,1,2,1])) :-
    example_puzzle(P, E, O),
    solve(P, E, O, [Row1 | _]).

test(solution_keeps_clues) :-
    example_puzzle(P, E, O),
    solve(P, E, O, S),
    append(P, FlatP), append(S, FlatS),
    maplist([Clue, Value] >> ( Clue =:= 0 -> true ; Clue =:= Value ), FlatP, FlatS).

test(three_suns_in_a_row, fail) :-
    length(Rest, 5),
    maplist(=([0,0,0,0,0,0]), Rest),
    solve([[1,1,1,0,0,0] | Rest], [], [], _).

test(too_many_moons, fail) :-
    length(Rest, 5),
    maplist(=([0,0,0,0,0,0]), Rest),
    solve([[2,2,1,2,2,0] | Rest], [], [], _).

test(equal_sign_is_respected, true(A == B)) :-
    empty_board(Board),
    solve(Board, [[0,0,0,1]], [], [[A, B | _] | _]).

test(opposite_sign_is_respected, true(A \== B)) :-
    empty_board(Board),
    solve(Board, [], [[0,0,0,1]], [[A, B | _] | _]).

test(contradictory_signs, fail) :-
    empty_board(Board),
    solve(Board, [[0,0,0,1]], [[0,0,0,1]], _).

test(empty_board_has_many_solutions, true(N == 2)) :-
    empty_board(Board),
    count_solutions(Board, [], [], 2, N).

:- end_tests(solve).

:- begin_tests(generate).

test(unique_solution, true(N == 1)) :-
    generate(hard, P, E, O),
    count_solutions(P, E, O, 2, N).

test(signs_match_solution) :-
    generate(easy, P, E, O),
    solve(P, E, O, S),
    forall(member([R1,C1,R2,C2], E),
           ( value(S, R1, C1, V), value(S, R2, C2, V) )),
    forall(member([R1,C1,R2,C2], O),
           ( value(S, R1, C1, V1), value(S, R2, C2, V2), V1 =\= V2 )).

test(bad_difficulty, error(type_error(_, impossible))) :-
    generate(impossible, _, _, _).

:- end_tests(generate).

:- begin_tests(hint).

test(hint_matches_solution, true(Value == Expected)) :-
    example_puzzle(P, E, O),
    hint(P, E, O, [Row, Col, Value]),
    solve(P, E, O, S),
    nth0(Row, S, SRow), nth0(Col, SRow, Expected).

test(hint_on_empty_cell) :-
    example_puzzle(P, E, O),
    hint(P, E, O, [Row, Col, _]),
    nth0(Row, P, PRow), nth0(Col, PRow, 0).

test(complete_board, true(Result == complete)) :-
    example_puzzle(P, E, O),
    solve(P, E, O, S),
    hint(S, E, O, Result).

test(unsolvable_board, true(Result == unsolvable)) :-
    example_puzzle(P, E, O),
    solve(P, E, O, [[A, B | Rest] | Rows]),
    % A solução começa com lua, lua: trocar por sol, sol quebra a linha.
    swap(A, A2), swap(B, B2),
    hint([[A2, B2 | Rest] | Rows], E, O, Result).

:- end_tests(hint).

empty_board(Board) :-
    length(Board, 6),
    maplist(=([0,0,0,0,0,0]), Board).

value(Grid, R, C, V) :- nth0(R, Grid, Row), nth0(C, Row, V).

swap(1, 2).
swap(2, 1).

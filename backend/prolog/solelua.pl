/*  solelua.pl: regras, resolvedor, gerador e dica do Sol e Lua.

    Tabuleiro 6x6. Cada casa tem um sol ou uma lua:
      - cada linha e coluna tem 3 sóis e 3 luas;
      - não pode haver três iguais seguidos;
      - "=" liga duas casas vizinhas com o mesmo símbolo;
      - "x" liga duas casas vizinhas com símbolos diferentes.

    Formato (o mesmo que o Python manda via janus):
      tabuleiro = 6 listas de 6 inteiros (0 vazia, 1 sol, 2 lua)
      sinais    = listas Equal e Opposite, cada sinal é [R1, C1, R2, C2]

    No terminal:
      ?- example_puzzle(P, E, O), solve(P, E, O, S), print_grid(S).
      ?- generate(hard, P, E, O), print_grid(P).
*/

:- module(solelua,
          [ solve/4,             % +Puzzle, +Equal, +Opposite, -Solution
            count_solutions/5,   % +Puzzle, +Equal, +Opposite, +Limit, -Count
            generate/4,          % +Difficulty, -Puzzle, -Equal, -Opposite
            hint/4,              % +Board, +Equal, +Opposite, -Result
            example_puzzle/3,    % -Puzzle, -Equal, -Opposite
            print_grid/1         % +Grid
          ]).

:- use_module(library(clpfd)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(random)).
:- use_module(library(solution_sequences)).


/* =========================================================================
   1. REGRAS
   ========================================================================= */

%!  sol_lua_constraints(?Rows, +Equal, +Opposite) is det.
%
%   Só declara as regras. Quem acha os valores é o labeling depois.
sol_lua_constraints(Rows, Equal, Opposite) :-
    length(Rows, 6),
    maplist(same_length(Rows), Rows),
    append(Rows, Cells),
    Cells ins 1..2,
    maplist(valid_line, Rows),
    transpose(Rows, Columns),
    maplist(valid_line, Columns),
    maplist(same_symbol(Rows), Equal),
    maplist(different_symbol(Rows), Opposite).

valid_line(Line) :-
    global_cardinality(Line, [1-3, 2-3]),
    no_three_in_a_row(Line).

%   Três sóis somam 3 e três luas somam 6; misturado dá 4 ou 5.
%   Escrito como soma, o CLP(FD) consegue propagar melhor que com
%   "não (A = B e B = C)".
no_three_in_a_row([A, B, C | Rest]) :-
    !,
    A + B + C #> 3,
    A + B + C #< 6,
    no_three_in_a_row([B, C | Rest]).
no_three_in_a_row(_).

same_symbol(Rows, [R1, C1, R2, C2]) :-
    cell(Rows, R1, C1, A),
    cell(Rows, R2, C2, B),
    A #= B.

different_symbol(Rows, [R1, C1, R2, C2]) :-
    cell(Rows, R1, C1, A),
    cell(Rows, R2, C2, B),
    A #\= B.

cell(Rows, R, C, Value) :-
    nth0(R, Rows, Row),
    nth0(C, Row, Value).


/* =========================================================================
   2. CASAS VAZIAS VIRAM VARIÁVEIS
   ========================================================================= */

grid_vars(Grid, Vars) :-
    maplist(maplist(cell_var), Grid, Vars).

cell_var(0, _) :- !.
cell_var(N, N).


/* =========================================================================
   3. RESOLVER
   ========================================================================= */

%!  solve(+Puzzle, +Equal, +Opposite, -Solution) is semidet.
solve(Puzzle, Equal, Opposite, Solution) :-
    grid_vars(Puzzle, Solution),
    sol_lua_constraints(Solution, Equal, Opposite),
    append(Solution, Cells),
    labeling([ff], Cells),
    !.

%!  count_solutions(+Puzzle, +Equal, +Opposite, +Limit, -Count) is det.
%
%   Com Limit = 2 dá para saber se a solução é única sem enumerar todas.
count_solutions(Puzzle, Equal, Opposite, Limit, Count) :-
    grid_vars(Puzzle, Rows),
    append(Rows, Cells),
    findall(x,
            limit(Limit, ( sol_lua_constraints(Rows, Equal, Opposite),
                           labeling([ff], Cells) )),
            Found),
    length(Found, Count).

unique_solution(Puzzle, Equal, Opposite) :-
    count_solutions(Puzzle, Equal, Opposite, 2, 1).


/* =========================================================================
   4. GERADOR
   =========================================================================

   1. sorteia um tabuleiro completo;
   2. escolhe alguns pares vizinhos e põe "=" ou "x" conforme o tabuleiro;
   3. vai apagando casas em ordem aleatória, desde que a solução continue
      única, até chegar no número de pistas do nível.
*/

%   level(Dificuldade, Sinais, Pistas)
level(easy,   8, 12).
level(medium, 6,  8).
level(hard,   4,  4).

%!  generate(+Difficulty, -Puzzle, -Equal, -Opposite) is det.
generate(Difficulty, Puzzle, Equal, Opposite) :-
    must_be(oneof([easy, medium, hard]), Difficulty),
    level(Difficulty, SignCount, Target),
    random_full_grid(Full),
    random_signs(Full, SignCount, Equal, Opposite),
    numlist(0, 35, Indexes),
    random_permutation(Indexes, Order),
    append(Full, FlatFull),
    dig_holes(Order, Target, Equal, Opposite, FlatFull, FlatPuzzle),
    rows_of_6(FlatPuzzle, Puzzle),
    !.

random_full_grid(Rows) :-
    length(Rows, 6),
    sol_lua_constraints(Rows, [], []),
    append(Rows, Cells),
    random_labeling(Cells),
    !.

%   Como label/1, mas tentando 1 e 2 em ordem aleatória.
random_labeling([]).
random_labeling([Var | Vars]) :-
    (   integer(Var)
    ->  true
    ;   random_permutation([1, 2], Values),
        member(Var, Values)
    ),
    random_labeling(Vars).

random_signs(Full, Count, Equal, Opposite) :-
    findall(Pair, neighbour_pair(Pair), Pairs),
    random_permutation(Pairs, Shuffled),
    length(Chosen, Count),
    append(Chosen, _, Shuffled),
    partition(equal_in(Full), Chosen, Equal, Opposite).

%   Cada casa com a da direita e com a de baixo.
neighbour_pair([R, C, R, C2]) :-
    between(0, 5, R),
    between(0, 4, C),
    C2 is C + 1.
neighbour_pair([R, C, R2, C]) :-
    between(0, 4, R),
    between(0, 5, C),
    R2 is R + 1.

%   O mesmo V nas duas chamadas: só passa se as casas forem iguais.
equal_in(Full, [R1, C1, R2, C2]) :-
    cell(Full, R1, C1, V),
    cell(Full, R2, C2, V).

dig_holes([], _, _, _, Flat, Flat).
dig_holes([Index | Rest], Target, Equal, Opposite, Flat0, Flat) :-
    clue_count(Flat0, Clues),
    (   Clues =< Target
    ->  Flat = Flat0
    ;   replace_nth0(Index, Flat0, 0, Candidate),
        rows_of_6(Candidate, CandidateRows),
        (   unique_solution(CandidateRows, Equal, Opposite)
        ->  Next = Candidate
        ;   Next = Flat0
        ),
        dig_holes(Rest, Target, Equal, Opposite, Next, Flat)
    ).

clue_count(Flat, N) :-
    include(\==(0), Flat, Clues),
    length(Clues, N).

replace_nth0(Index, List, Elem, NewList) :-
    nth0(Index, List, _, Rest),
    nth0(Index, NewList, Elem, Rest).

rows_of_6([], []).
rows_of_6(Flat, [Row | Rows]) :-
    length(Row, 6),
    append(Row, Rest, Flat),
    rows_of_6(Rest, Rows).


/* =========================================================================
   5. DICA
   ========================================================================= */

%!  hint(+Board, +Equal, +Opposite, -Result) is det.
%
%   Result = [Row, Col, Value], complete ou unsolvable.
%   É lista e não termo composto porque o janus não converte termos.
hint(Board, Equal, Opposite, Result) :-
    (   solve(Board, Equal, Opposite, Solution)
    ->  empty_positions(Board, Empty),
        (   Empty == []
        ->  Result = complete
        ;   random_member(Row-Col, Empty),
            cell(Solution, Row, Col, Value),
            Result = [Row, Col, Value]
        )
    ;   Result = unsolvable
    ).

empty_positions(Board, Positions) :-
    findall(R-C, (nth0(R, Board, Row), nth0(C, Row, 0)), Positions).


/* =========================================================================
   6. TERMINAL
   ========================================================================= */

%   Gerado com generate(medium, ...); tem solução única.
example_puzzle([[0,0,0, 1,0,0],
                [0,0,0, 0,2,2],
                [0,2,1, 0,0,0],
                [1,0,0, 0,0,0],
                [0,0,0, 1,0,2],
                [0,0,0, 0,0,0]],
               [[4,5,5,5], [5,0,5,1]],
               [[2,2,2,3], [1,1,2,1], [3,2,4,2], [0,3,0,4]]).

print_grid(Grid) :-
    forall(member(Row, Grid), (maplist(format_cell, Row), nl)).

format_cell(0) :- write(' .').
format_cell(1) :- write(' S').
format_cell(2) :- write(' L').

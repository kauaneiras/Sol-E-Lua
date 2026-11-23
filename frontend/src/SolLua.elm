module SolLua exposing
    ( Board
    , Cell(..)
    , Position
    , Puzzle
    , Sign
    , SignKind(..)
    , Symbol(..)
    , cellAt
    , clearGuesses
    , conflicts
    , cycle
    , empty
    , fromLists
    , isComplete
    , isGiven
    , isGuess
    , isRevealed
    , positions
    , revealSolution
    , setCell
    , symbolOf
    , toLists
    )

{-| Tabuleiro e regras do Sol e Lua. Módulo puro: sem HTTP e sem HTML.
-}

import Array exposing (Array)
import Set exposing (Set)



-- TIPOS


type Symbol
    = Sun
    | Moon


{-| A origem do símbolo fica no próprio tipo, então não tem como uma pista
ser tratada como palpite.
-}
type Cell
    = Given Symbol
    | Guess Symbol
    | Revealed Symbol
    | Empty


type alias Position =
    ( Int, Int )


{-| 36 casas, linha por linha: (linha, coluna) fica em `linha * 6 + coluna`.
-}
type alias Board =
    Array Cell


type SignKind
    = Equal
    | Opposite


type alias Sign =
    { from : Position
    , to : Position
    , kind : SignKind
    }


{-| Os sinais não mudam durante o jogo, só o tabuleiro.
-}
type alias Puzzle =
    { board : Board
    , signs : List Sign
    }


size : Int
size =
    6



-- CONVERSÃO


empty : Board
empty =
    Array.repeat (size * size) Empty


{-| Formato da API: 0 vazia, 1 sol, 2 lua. O que vem preenchido é pista.
-}
fromLists : List (List Int) -> Board
fromLists lists =
    lists
        |> List.concat
        |> List.map
            (\n ->
                case n of
                    1 ->
                        Given Sun

                    2 ->
                        Given Moon

                    _ ->
                        Empty
            )
        |> Array.fromList


toLists : Board -> List (List Int)
toLists board =
    board
        |> Array.toList
        |> List.map (symbolOf >> Maybe.map symbolToInt >> Maybe.withDefault 0)
        |> chunksOf size


symbolToInt : Symbol -> Int
symbolToInt symbol =
    case symbol of
        Sun ->
            1

        Moon ->
            2


chunksOf : Int -> List a -> List (List a)
chunksOf n list =
    case list of
        [] ->
            []

        _ ->
            List.take n list :: chunksOf n (List.drop n list)



-- CONSULTAS


symbolOf : Cell -> Maybe Symbol
symbolOf cell =
    case cell of
        Given symbol ->
            Just symbol

        Guess symbol ->
            Just symbol

        Revealed symbol ->
            Just symbol

        Empty ->
            Nothing


cellAt : Position -> Board -> Cell
cellAt ( row, col ) board =
    Array.get (row * size + col) board
        |> Maybe.withDefault Empty


symbolAt : Board -> Position -> Maybe Symbol
symbolAt board position =
    symbolOf (cellAt position board)


isGiven : Cell -> Bool
isGiven cell =
    case cell of
        Given _ ->
            True

        _ ->
            False


isGuess : Cell -> Bool
isGuess cell =
    case cell of
        Guess _ ->
            True

        _ ->
            False


isRevealed : Cell -> Bool
isRevealed cell =
    case cell of
        Revealed _ ->
            True

        _ ->
            False


positions : List Position
positions =
    List.concat rowPositions


rowPositions : List (List Position)
rowPositions =
    List.range 0 (size - 1)
        |> List.map (\row -> List.map (\col -> ( row, col )) (List.range 0 (size - 1)))


columnPositions : List (List Position)
columnPositions =
    List.range 0 (size - 1)
        |> List.map (\col -> List.map (\row -> ( row, col )) (List.range 0 (size - 1)))


{-| Casas que quebram alguma regra: trinca, mais de 3 iguais na linha ou
coluna, ou sinal desrespeitado.

Fica aqui e não no Prolog porque roda a cada clique e não precisa de busca.

-}
conflicts : List Sign -> Board -> Set Position
conflicts signs board =
    (List.concatMap (lineConflicts board) (rowPositions ++ columnPositions)
        ++ List.concatMap (signConflicts board) signs
    )
        |> Set.fromList


lineConflicts : Board -> List Position -> List Position
lineConflicts board line =
    threeInARow board line ++ tooMany board Sun line ++ tooMany board Moon line


threeInARow : Board -> List Position -> List Position
threeInARow board line =
    let
        sameSymbol ( a, b, c ) =
            let
                symbol =
                    symbolAt board a
            in
            symbol /= Nothing && symbol == symbolAt board b && symbol == symbolAt board c
    in
    triples line
        |> List.filter sameSymbol
        |> List.concatMap (\( a, b, c ) -> [ a, b, c ])


{-| `[1, 2, 3, 4]` vira `[ ( 1, 2, 3 ), ( 2, 3, 4 ) ]`.
-}
triples : List a -> List ( a, a, a )
triples list =
    case list of
        a :: b :: c :: rest ->
            ( a, b, c ) :: triples (b :: c :: rest)

        _ ->
            []


tooMany : Board -> Symbol -> List Position -> List Position
tooMany board symbol line =
    let
        matching =
            List.filter (\position -> symbolAt board position == Just symbol) line
    in
    if List.length matching > size // 2 then
        matching

    else
        []


signConflicts : Board -> Sign -> List Position
signConflicts board { from, to, kind } =
    case ( symbolAt board from, symbolAt board to ) of
        ( Just a, Just b ) ->
            let
                respected =
                    case kind of
                        Equal ->
                            a == b

                        Opposite ->
                            a /= b
            in
            if respected then
                []

            else
                [ from, to ]

        -- Com uma das casas vazia ainda não dá para dizer nada.
        _ ->
            []


isComplete : List Sign -> Board -> Bool
isComplete signs board =
    List.all (\cell -> symbolOf cell /= Nothing) (Array.toList board)
        && Set.isEmpty (conflicts signs board)



-- ALTERAÇÕES


{-| Pistas não podem ser alteradas.
-}
setCell : Position -> Cell -> Board -> Board
setCell (( row, col ) as position) cell board =
    case cellAt position board of
        Given _ ->
            board

        _ ->
            Array.set (row * size + col) cell board


{-| Clique: vazia -> sol -> lua -> vazia. Uma casa revelada pelo Prolog volta
a ser do jogador.
-}
cycle : Cell -> Cell
cycle cell =
    case cell of
        Given _ ->
            cell

        Empty ->
            Guess Sun

        Guess Sun ->
            Guess Moon

        Guess Moon ->
            Empty

        Revealed Sun ->
            Guess Moon

        Revealed Moon ->
            Empty


revealSolution : Board -> Board -> Board
revealSolution solution board =
    Array.indexedMap
        (\index cell ->
            case cell of
                Given _ ->
                    cell

                _ ->
                    Array.get index solution
                        |> Maybe.andThen symbolOf
                        |> Maybe.map Revealed
                        |> Maybe.withDefault cell
        )
        board


clearGuesses : Board -> Board
clearGuesses board =
    Array.map
        (\cell ->
            if isGiven cell then
                cell

            else
                Empty
        )
        board

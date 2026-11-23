module Main exposing (main)

{-| Tela do Sol e Lua (Model, update, view).
-}

import Api exposing (Difficulty(..))
import Browser
import Html exposing (Html, aside, button, div, footer, h1, header, input, label, li, main_, span, text, ul)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, style, type_, value)
import Html.Events exposing (onCheck, onClick)
import Process
import Set exposing (Set)
import SolLua exposing (Board, Cell(..), Position, Puzzle, Sign, SignKind(..), Symbol(..))
import Task



-- MAIN


main : Program Flags Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }



-- MODEL


{-| Vem do main.js, que lê o tema salvo no localStorage.
-}
type alias Flags =
    { darkTheme : Bool
    }


{-| `edits` conta as mudanças no tabuleiro. Cada mudança dispara um
temporizador que carrega o número da edição; quando ele termina, só mostra
os conflitos se ninguém mexeu no tabuleiro desde então.
-}
type alias Model =
    { puzzle : Puzzle
    , difficulty : Difficulty
    , darkTheme : Bool
    , loading : Bool
    , error : Maybe String
    , edits : Int
    , visibleConflicts : Set Position
    }


init : Flags -> ( Model, Cmd Msg )
init flags =
    ( { puzzle = { board = SolLua.empty, signs = [] }
      , difficulty = Medium
      , darkTheme = flags.darkTheme
      , loading = True
      , error = Nothing
      , edits = 0
      , visibleConflicts = Set.empty
      }
    , Api.generate Medium GotPuzzle
    )



-- UPDATE


type Msg
    = NewGame Difficulty
    | GotPuzzle (Result String Puzzle)
    | CellClicked Position
    | ThemeToggled Bool
    | HintRequested
    | GotHint (Result String Api.Hint)
    | SolveRequested
    | GotSolution (Result String Board)
    | ResetRequested
    | ErrorDismissed
    | ConflictTimerEnded Int


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NewGame difficulty ->
            ( { model | difficulty = difficulty, loading = True, error = Nothing }
            , Api.generate difficulty GotPuzzle
            )

        GotPuzzle (Ok puzzle) ->
            ( { model | puzzle = puzzle, loading = False, visibleConflicts = Set.empty }, Cmd.none )

        GotPuzzle (Err error) ->
            ( failed error model, Cmd.none )

        CellClicked position ->
            let
                newCell =
                    SolLua.cycle (SolLua.cellAt position model.puzzle.board)
            in
            boardChanged (updateBoard (SolLua.setCell position newCell) model)

        ThemeToggled dark ->
            -- Quem troca as cores é o CSS; aqui só guardamos o estado.
            ( { model | darkTheme = dark }, Cmd.none )

        HintRequested ->
            ( { model | loading = True, error = Nothing }
            , Api.hint model.puzzle GotHint
            )

        GotHint (Ok { position, symbol }) ->
            boardChanged (updateBoard (SolLua.setCell position (Revealed symbol)) { model | loading = False })

        GotHint (Err error) ->
            ( failed error model, Cmd.none )

        SolveRequested ->
            -- Só as pistas vão para o Prolog: um palpite errado do jogador
            -- deixaria o tabuleiro sem solução.
            ( { model | loading = True, error = Nothing }
            , Api.solve (withBoard (SolLua.clearGuesses model.puzzle.board) model.puzzle) GotSolution
            )

        GotSolution (Ok solution) ->
            boardChanged (updateBoard (SolLua.revealSolution solution) { model | loading = False })

        GotSolution (Err error) ->
            ( failed error model, Cmd.none )

        ResetRequested ->
            boardChanged (updateBoard SolLua.clearGuesses { model | error = Nothing })

        ErrorDismissed ->
            ( { model | error = Nothing }, Cmd.none )

        ConflictTimerEnded edit ->
            if edit == model.edits then
                ( { model | visibleConflicts = currentConflicts model }, Cmd.none )

            else
                -- O tabuleiro mudou de novo; um temporizador mais novo cuida disso.
                ( model, Cmd.none )


{-| Quanto tempo esperar, em milissegundos, antes de marcar os conflitos.
-}
conflictDelay : Float
conflictDelay =
    1500


{-| Chamado depois de toda mudança no tabuleiro. Um conflito que foi
corrigido some na hora (a interseção com os conflitos atuais); os novos só
aparecem quando o temporizador terminar.
-}
boardChanged : Model -> ( Model, Cmd Msg )
boardChanged model =
    let
        edit =
            model.edits + 1
    in
    ( { model
        | edits = edit
        , visibleConflicts = Set.intersect model.visibleConflicts (currentConflicts model)
      }
    , Process.sleep conflictDelay
        |> Task.perform (\_ -> ConflictTimerEnded edit)
    )


currentConflicts : Model -> Set Position
currentConflicts model =
    SolLua.conflicts model.puzzle.signs model.puzzle.board


failed : String -> Model -> Model
failed error model =
    { model | loading = False, error = Just error }


updateBoard : (Board -> Board) -> Model -> Model
updateBoard change model =
    { model | puzzle = withBoard (change model.puzzle.board) model.puzzle }


withBoard : Board -> Puzzle -> Puzzle
withBoard board puzzle =
    { puzzle | board = board }



-- VIEW


view : Model -> Html Msg
view model =
    div [ class "app" ]
        [ header [ class "app-header" ]
            [ div [ class "app-container app-header-content" ]
                [ h1 [ class "app-title" ] [ text "Sol e Lua" ]
                , viewThemeToggle model
                ]
            ]
        , main_ [ class "app-main" ]
            [ div [ class "app-container game" ]
                [ viewBoard model.visibleConflicts model.puzzle
                , aside [ class "side-panel" ]
                    [ span [ class "panel-label" ] [ text "Novo jogo" ]
                    , viewDifficulty model
                    , div [ class "message-area" ] [ viewMessages model ]
                    , span [ class "panel-label" ] [ text "Regras" ]
                    , viewRules
                    , span [ class "panel-label" ] [ text "Ajuda" ]
                    , viewActions model
                    ]
                ]
            ]
        , footer [ class "app-footer" ]
            [ text "Clique numa casa para trocar: vazia → ☀ → ☾ → vazia." ]
        ]


viewThemeToggle : Model -> Html Msg
viewThemeToggle model =
    label [ class "theme-toggle", attribute "aria-label" "Alternar tema claro/escuro" ]
        [ input
            [ type_ "checkbox"
            , class "theme-controller"
            , value "dark"
            , checked model.darkTheme
            , onCheck ThemeToggled
            ]
            []
        , span [ class "swap-off" ] [ text "☀" ]
        , span [ class "swap-on" ] [ text "☾" ]
        ]


viewDifficulty : Model -> Html Msg
viewDifficulty model =
    let
        option difficulty =
            button
                [ class "difficulty-option"
                , classList [ ( "difficulty-option--active", difficulty == model.difficulty ) ]
                , disabled model.loading
                , onClick (NewGame difficulty)
                ]
                [ text (Api.difficultyLabel difficulty) ]
    in
    div [ class "difficulty-picker" ] (List.map option [ Easy, Medium, Hard ])


viewMessages : Model -> Html Msg
viewMessages model =
    case ( model.error, model.loading ) of
        ( Just error, _ ) ->
            div [ class "message message--error" ]
                [ span [] [ text error ]
                , button [ class "message-close", onClick ErrorDismissed ] [ text "✕" ]
                ]

        ( Nothing, True ) ->
            div [ class "message message--loading" ]
                [ span [ class "spinner" ] []
                , span [] [ text "O Prolog está pensando..." ]
                ]

        ( Nothing, False ) ->
            if SolLua.isComplete model.puzzle.signs model.puzzle.board then
                div [ class "message message--success" ]
                    [ text (completionMessage model.puzzle.board) ]

            else
                text ""


completionMessage : Board -> String
completionMessage board =
    let
        usedHelp =
            List.any (\pos -> SolLua.isRevealed (SolLua.cellAt pos board)) SolLua.positions
    in
    if usedHelp then
        "Resolvido (com ajuda do Prolog)."

    else
        "Parabéns! Você resolveu o puzzle!"


viewRules : Html Msg
viewRules =
    ul [ class "rules" ]
        [ li [] [ text "Cada linha e coluna tem 3 ☀ e 3 ☾." ]
        , li [] [ text "Nunca três símbolos iguais seguidos." ]
        , li [] [ text "= liga casas com o mesmo símbolo." ]
        , li [] [ text "× liga casas com símbolos diferentes." ]
        ]


{-| Os sinais ficam numa camada por cima das casas (`.signs` no CSS).
-}
viewBoard : Set Position -> Puzzle -> Html Msg
viewBoard conflicts { board, signs } =
    div
        [ class "board"
        , classList [ ( "board--solved", SolLua.isComplete signs board ) ]
        ]
        (List.map (viewCell board conflicts) SolLua.positions
            ++ [ div [ class "signs" ] (List.map viewSign signs) ]
        )


viewCell : Board -> Set Position -> Position -> Html Msg
viewCell board conflicts (( row, col ) as position) =
    let
        cell =
            SolLua.cellAt position board
    in
    button
        [ class "cell"
        , classList
            [ ( "cell--conflict", Set.member position conflicts )
            , ( "cell--given", SolLua.isGiven cell )
            , ( "cell--guess", SolLua.isGuess cell )
            , ( "cell--revealed", SolLua.isRevealed cell )
            ]
        , attribute "aria-label"
            ("Linha " ++ String.fromInt (row + 1) ++ ", coluna " ++ String.fromInt (col + 1))
        , onClick (CellClicked position)
        ]
        [ case SolLua.symbolOf cell of
            Just Sun ->
                span [ class "cell-value cell-symbol cell-symbol--sun" ] [ text "☀" ]

            Just Moon ->
                span [ class "cell-value cell-symbol cell-symbol--moon" ] [ text "☾" ]

            Nothing ->
                text ""
        ]


{-| O centro da casa (r, c) fica em ((c + 0.5) / 6, (r + 0.5) / 6) do
tabuleiro; o sinal vai na média dos centros das duas casas.
-}
viewSign : Sign -> Html Msg
viewSign { from, to, kind } =
    let
        ( r1, c1 ) =
            from

        ( r2, c2 ) =
            to

        percent a b =
            String.fromFloat ((toFloat (a + b) / 2 + 0.5) / 6 * 100) ++ "%"
    in
    span
        [ class "sign"
        , style "left" (percent c1 c2)
        , style "top" (percent r1 r2)
        ]
        [ text
            (case kind of
                Equal ->
                    "="

                Opposite ->
                    "×"
            )
        ]


viewActions : Model -> Html Msg
viewActions model =
    let
        nothingToReveal =
            model.loading || SolLua.isComplete model.puzzle.signs model.puzzle.board
    in
    div [ class "actions" ]
        [ button [ class "action-button action-button--hint", disabled nothingToReveal, onClick HintRequested ] [ text "Dica" ]
        , button [ class "action-button action-button--solve", disabled nothingToReveal, onClick SolveRequested ] [ text "Resolver" ]
        , button [ class "action-button action-button--reset", disabled model.loading, onClick ResetRequested ] [ text "Limpar" ]
        ]

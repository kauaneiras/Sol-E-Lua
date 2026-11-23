module Api exposing
    ( Difficulty(..)
    , Hint
    , difficultyLabel
    , generate
    , hint
    , solve
    )

{-| Requisições ao backend. As URLs `/api/...` são repassadas pelo Vite para
a porta 8000 (vite.config.js).
-}

import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode
import SolLua exposing (Board, Position, Puzzle, Sign, SignKind(..), Symbol(..))


type Difficulty
    = Easy
    | Medium
    | Hard


difficultyLabel : Difficulty -> String
difficultyLabel difficulty =
    case difficulty of
        Easy ->
            "Fácil"

        Medium ->
            "Médio"

        Hard ->
            "Difícil"


{-| Os mesmos átomos que o Prolog espera em generate/4.
-}
difficultyToString : Difficulty -> String
difficultyToString difficulty =
    case difficulty of
        Easy ->
            "easy"

        Medium ->
            "medium"

        Hard ->
            "hard"


type alias Hint =
    { position : Position
    , symbol : Symbol
    }



-- REQUISIÇÕES


generate : Difficulty -> (Result String Puzzle -> msg) -> Cmd msg
generate difficulty toMsg =
    Http.post
        { url = "/api/generate"
        , body =
            Http.jsonBody
                (Encode.object [ ( "difficulty", Encode.string (difficultyToString difficulty) ) ])
        , expect = expectJson toMsg puzzleDecoder
        }


solve : Puzzle -> (Result String Board -> msg) -> Cmd msg
solve puzzle toMsg =
    Http.post
        { url = "/api/solve"
        , body = Http.jsonBody (encodePuzzle puzzle)
        , expect = expectJson toMsg (Decode.field "board" boardDecoder)
        }


hint : Puzzle -> (Result String Hint -> msg) -> Cmd msg
hint puzzle toMsg =
    Http.post
        { url = "/api/hint"
        , body = Http.jsonBody (encodePuzzle puzzle)
        , expect = expectJson toMsg hintDecoder
        }



-- JSON
--
-- Na API os sinais vêm em duas listas ("equal" e "opposite"), cada sinal
-- como [linha1, coluna1, linha2, coluna2]. Aqui viram uma lista só de Sign.


encodePuzzle : Puzzle -> Encode.Value
encodePuzzle { board, signs } =
    let
        encodeSigns kind =
            signs
                |> List.filter (\sign -> sign.kind == kind)
                |> Encode.list encodeSign
    in
    Encode.object
        [ ( "board", Encode.list (Encode.list Encode.int) (SolLua.toLists board) )
        , ( "equal", encodeSigns Equal )
        , ( "opposite", encodeSigns Opposite )
        ]


encodeSign : Sign -> Encode.Value
encodeSign { from, to } =
    let
        ( r1, c1 ) =
            from

        ( r2, c2 ) =
            to
    in
    Encode.list Encode.int [ r1, c1, r2, c2 ]


boardDecoder : Decoder Board
boardDecoder =
    Decode.list (Decode.list Decode.int)
        |> Decode.map SolLua.fromLists


puzzleDecoder : Decoder Puzzle
puzzleDecoder =
    Decode.map3 (\board equal opposite -> Puzzle board (equal ++ opposite))
        (Decode.field "board" boardDecoder)
        (Decode.field "equal" (Decode.list (signDecoder Equal)))
        (Decode.field "opposite" (Decode.list (signDecoder Opposite)))


{-| Só aceita listas com exatamente 4 números.
-}
signDecoder : SignKind -> Decoder Sign
signDecoder kind =
    Decode.list Decode.int
        |> Decode.andThen
            (\coords ->
                case coords of
                    [ r1, c1, r2, c2 ] ->
                        Decode.succeed { from = ( r1, c1 ), to = ( r2, c2 ), kind = kind }

                    _ ->
                        Decode.fail "um sinal deve ter 4 números"
            )


hintDecoder : Decoder Hint
hintDecoder =
    Decode.map3 (\row col symbol -> Hint ( row, col ) symbol)
        (Decode.field "row" Decode.int)
        (Decode.field "col" Decode.int)
        (Decode.field "value" symbolDecoder)


symbolDecoder : Decoder Symbol
symbolDecoder =
    Decode.int
        |> Decode.andThen
            (\n ->
                case n of
                    1 ->
                        Decode.succeed Sun

                    2 ->
                        Decode.succeed Moon

                    _ ->
                        Decode.fail ("símbolo desconhecido: " ++ String.fromInt n)
            )



-- ERROS
--
-- O Http.expectJson padrão joga fora o corpo das respostas 422, e é ali que
-- o backend manda a mensagem ("detail"). Por isso esta versão própria.


expectJson : (Result String a -> msg) -> Decoder a -> Http.Expect msg
expectJson toMsg decoder =
    Http.expectStringResponse toMsg <|
        \response ->
            case response of
                Http.GoodStatus_ _ body ->
                    Decode.decodeString decoder body
                        |> Result.mapError (\_ -> "Resposta inesperada do servidor.")

                Http.BadStatus_ metadata body ->
                    Err (errorDetail metadata.statusCode body)

                Http.BadUrl_ url ->
                    Err ("URL inválida: " ++ url)

                Http.Timeout_ ->
                    Err "O servidor demorou demais para responder."

                Http.NetworkError_ ->
                    Err "Não foi possível falar com o servidor. O backend está rodando?"


errorDetail : Int -> String -> String
errorDetail status body =
    case Decode.decodeString (Decode.field "detail" Decode.string) body of
        Ok detail ->
            detail

        Err _ ->
            "Erro no servidor (código " ++ String.fromInt status ++ ")."

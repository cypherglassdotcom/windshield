port module Main exposing (..)

import Html
import Model exposing (Model, Msg, Flags)
import View exposing (view)
import Update exposing (init, update, subscriptions)


main : Program Flags Model Msg
main =
    Html.programWithFlags
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }

module Handlers exposing (..)

import Model exposing (..)
import Decoders exposing (..)
import Utils exposing (newErrorNotification)
import Phoenix.Socket
import Phoenix.Channel
import Phoenix.Push
import Json.Encode as JE
import Json.Decode as JD
import Http


submitAdminLogin : Model -> Cmd Msg
submitAdminLogin model =
    let
        url =
            model.backendServer ++ "/api/auth"

        body =
            JE.object
                [ ( "password", JE.string model.adminPassword ) ]

        request =
            Http.request
                { method = "POST"
                , headers = []
                , url = url
                , body = Http.jsonBody body
                , expect = Http.expectJson userDecoder
                , timeout = Nothing
                , withCredentials = False
                }

        cmd =
            Http.send AuthResponse request
    in
        cmd


handleReceiveWsError : Model -> JE.Value -> ( Model, Cmd Msg )
handleReceiveWsError model errMsg =
    case JD.decodeValue wsErrorDecoder errMsg of
        Ok str ->
            let
                notifications =
                    Notification (Error str) model.currentTime (toString model.currentTime)
                        :: model.notifications
            in
                ( { model
                    | notifications = notifications
                    , isLoading = model.isLoading - 1
                  }
                , Cmd.none
                )

        Err _ ->
            newErrorNotification model "Error in received message from WINDSHIELD server" True


joinChannel : Model -> ( Model, Cmd Msg )
joinChannel model =
    let
        channel =
            Phoenix.Channel.init "monitor:main"
                |> Phoenix.Channel.onJoin (always (ShowJoinedMessage "Connected to WINDSHIELD Server"))
                |> Phoenix.Channel.onClose (always (ShowLeftMessage "WINDSHIELD Server Connection Closed"))

        ( phxSocket, phxCmd ) =
            Phoenix.Socket.join channel model.phxSocket
    in
        ( { model | phxSocket = phxSocket }
        , Cmd.map PhoenixMsg phxCmd
        )


retrieveMonitorData : Model -> String -> ( Model, Cmd Msg )
retrieveMonitorData model dataMsg =
    let
        push_ =
            Phoenix.Push.init dataMsg "monitor:main"
                |> Phoenix.Push.withPayload JE.null

        ( phxSocket, phxCmd ) =
            Phoenix.Socket.push push_ model.phxSocket
    in
        ( { model | phxSocket = phxSocket }
        , Cmd.map PhoenixMsg phxCmd
        )


submitSettings : Model -> ( Model, Cmd Msg )
submitSettings model =
    let
        push_ =
            Phoenix.Push.init "update_settings" "monitor:main"
                |> Phoenix.Push.withPayload
                    (settingsEncoder model.settingsForm model.user.token)

        ( phxSocket, phxCmd ) =
            Phoenix.Socket.push push_ model.phxSocket
    in
        ( { model | phxSocket = phxSocket }
        , Cmd.map PhoenixMsg phxCmd
        )


getNodeChainInfo : Model -> String -> ( Model, Cmd Msg )
getNodeChainInfo model account =
    let
        push_ =
            Phoenix.Push.init "get_node_chain_info" "monitor:main"
                |> Phoenix.Push.withPayload
                    (accountEncoder account)

        ( phxSocket, phxCmd ) =
            Phoenix.Socket.push push_ model.phxSocket
    in
        ( { model | phxSocket = phxSocket }
        , Cmd.map PhoenixMsg phxCmd
        )


submitNode : Model -> ( Model, Cmd Msg )
submitNode model =
    let
        push_ =
            Phoenix.Push.init "upsert_node" "monitor:main"
                |> Phoenix.Push.withPayload
                    (nodeEncoder model.nodeForm model.user.token)

        ( phxSocket, phxCmd ) =
            Phoenix.Socket.push push_ model.phxSocket
    in
        ( { model | phxSocket = phxSocket }
        , Cmd.map PhoenixMsg phxCmd
        )


submitArchive : Model -> Node -> Bool -> ( Model, Cmd Msg )
submitArchive model node isArchive =
    let
        push_ =
            Phoenix.Push.init "archive_restore_node" "monitor:main"
                |> Phoenix.Push.withPayload
                    (nodeArchiveEncoder model.user.token node.account isArchive)

        ( phxSocket, phxCmd ) =
            Phoenix.Socket.push push_ model.phxSocket
    in
        ( { model | phxSocket = phxSocket }
        , Cmd.map PhoenixMsg phxCmd
        )

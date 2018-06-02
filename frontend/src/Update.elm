port module Update exposing (..)

import Model exposing (..)
import Date
import Date.Extra.Core as Core
import Time
import Phoenix.Socket
import Phoenix.Channel
import Phoenix.Push
import Json.Encode as JE
import Json.Decode as JD
import Json.Decode.Pipeline as JDP
import Http


-- Ports and Subscriptions


port signOut : () -> Cmd msg


port signedIn : JD.Value -> Cmd msg


port playSound : () -> Cmd msg


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every Time.second Tick
        , Phoenix.Socket.listen model.phxSocket PhoenixMsg
        ]



-- Init


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        initialModel =
            initModel flags

        ( model, cmd ) =
            joinChannel initialModel
    in
        ( model, cmd )


initModel : Flags -> Model
initModel flags =
    let
        content =
            Home

        phxSocket =
            initPhxSocket flags.socketServer
    in
        { initialModel
            | user = flags.user
            , socketServer = flags.socketServer
            , backendServer = flags.backendServer
            , phxSocket = phxSocket
            , content = content
        }


initialModel : Model
initialModel =
    { isLoading = 0
    , isMuted = False
    , showHelp = False
    , showNode = False
    , showArchivedNodes = False
    , showAdminLogin = False
    , showArchiveConfirmation = False
    , adminPassword = ""
    , user = User "" "" 0
    , socketServer = ""
    , backendServer = ""
    , content = Home
    , socketsConnected = False
    , currentTime = 0
    , notifications = []
    , producers = []
    , nodes = []
    , principalNode = ""
    , currentProducer = Nothing
    , phxSocket = initPhxSocket ""
    , monitorConnected = False
    , monitorState = MonitorState InitialMonitor 0
    , nodeForm = newNode
    , showNodeChainInfo = False
    , viewingNode = Nothing
    , chainInfo = Nothing
    , settings = Settings "" 0 0 0 0 0 0 0
    , settingsForm = Settings "" 0 0 0 0 0 0 0
    , editSettingsForm = False
    , alerts = []
    }


initPhxSocket : String -> Phoenix.Socket.Socket Msg
initPhxSocket socketServer =
    Phoenix.Socket.init socketServer
        -- |> Phoenix.Socket.withDebug
        |> Phoenix.Socket.on "tick_stats" "monitor:main" ReceiveTickStats
        |> Phoenix.Socket.on "get_state" "monitor:main" ReceiveMonitorState
        |> Phoenix.Socket.on "get_alerts" "monitor:main" ReceiveAlerts
        |> Phoenix.Socket.on "get_nodes" "monitor:main" ReceiveNodes
        |> Phoenix.Socket.on "get_node_chain_info" "monitor:main" ReceiveNodeChainInfo
        |> Phoenix.Socket.on "get_nodes_fail" "monitor:main" ReceiveNodesFail
        |> Phoenix.Socket.on "get_producers" "monitor:main" ReceiveProducers
        |> Phoenix.Socket.on "get_producers_fail" "monitor:main" ReceiveProducersFail
        |> Phoenix.Socket.on "get_settings" "monitor:main" ReceiveSettings
        |> Phoenix.Socket.on "get_settings_fail" "monitor:main" ReceiveSettingsFail
        |> Phoenix.Socket.on "update_settings" "monitor:main" ReceiveSettings
        |> Phoenix.Socket.on "update_settings_fail" "monitor:main" ReceiveUpdateSettingsFail
        |> Phoenix.Socket.on "upsert_node" "monitor:main" ReceiveUpsertNode
        |> Phoenix.Socket.on "upsert_node_fail" "monitor:main" ReceiveUpsertNodeFail
        |> Phoenix.Socket.on "tick_producer" "monitor:main" ReceiveProducer
        |> Phoenix.Socket.on "tick_node" "monitor:main" ReceiveNode
        |> Phoenix.Socket.on "emit_alert" "monitor:main" ReceiveAlert
        |> Phoenix.Socket.on "archive_restore_node" "monitor:main" ReceiveUpsertNode
        |> Phoenix.Socket.on "archive_restore_node_fail" "monitor:main" ReceiveArchiveRestoreFail



-- Update


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        JoinChannel ->
            joinChannel model

        ShowJoinedMessage str ->
            let
                notifications =
                    Notification (Success str)
                        model.currentTime
                        "joinedChannelMessage"
                        :: model.notifications

                ( phxModel1, cmdRetrieveSettings ) =
                    retrieveMonitorData model "get_settings"

                ( phxModel2, cmdRetrieveNodes ) =
                    retrieveMonitorData phxModel1 "get_nodes"

                ( phxModel3, cmdRetrieveProducers ) =
                    retrieveMonitorData phxModel2 "get_producers"

                ( phxModel4, cmdRetrieveAlerts ) =
                    retrieveMonitorData phxModel3 "get_alerts"

                ( newModel, cmdRetrieveState ) =
                    retrieveMonitorData phxModel4 "get_state"
            in
                ( { newModel
                    | monitorConnected = True
                    , notifications = notifications
                    , isLoading = model.isLoading + 5
                  }
                , Cmd.batch
                    [ cmdRetrieveSettings
                    , cmdRetrieveNodes
                    , cmdRetrieveProducers
                    , cmdRetrieveAlerts
                    , cmdRetrieveState
                    ]
                )

        ShowLeftMessage str ->
            let
                notifications =
                    Notification (Error str) model.currentTime "leftChannelMessage"
                        :: model.notifications
            in
                ( { model | monitorConnected = False, notifications = notifications }
                , audioCmd model.isMuted
                )

        PhoenixMsg str ->
            let
                ( phxSocket, phxCmd ) =
                    Phoenix.Socket.update str model.phxSocket
            in
                ( { model | phxSocket = phxSocket }
                , Cmd.map PhoenixMsg phxCmd
                )

        ReceiveTickStats raw ->
            case JD.decodeValue statsDecoder raw of
                Ok stats ->
                    let
                        monitorState =
                            model.monitorState

                        newMonitorState =
                            { monitorState
                                | lastBlockNum = stats.lastBlockNum
                                , status = stats.status
                            }
                    in
                        ( { model | monitorState = newMonitorState }, Cmd.none )

                Err err ->
                    Debug.log err ( model, Cmd.none )

        ReceiveNodes raw ->
            case JD.decodeValue nodesRowsDecoder raw of
                Ok nodes ->
                    ( { model
                        | nodes = mergeProductionToNodes nodes model.producers
                        , isLoading = model.isLoading - 1
                      }
                    , Cmd.none
                    )

                Err error ->
                    Debug.crash error
                        ( { model | isLoading = model.isLoading - 1 }, Cmd.none )

        ReceiveNodeChainInfo raw ->
            case JD.decodeValue chainInfoDataDecoder raw of
                Ok chainInfoData ->
                    ( { model
                        | chainInfo = Just chainInfoData.chainInfo
                        , showNodeChainInfo = True
                        , isLoading = model.isLoading - 1
                      }
                    , Cmd.none
                    )

                Err error ->
                    Debug.crash error
                        ( { model | isLoading = model.isLoading - 1 }, Cmd.none )

        ReceiveProducers raw ->
            case JD.decodeValue producersRowsDecoder raw of
                Ok producers ->
                    ( { model
                        | producers = producers
                        , isLoading = model.isLoading - 1
                        , nodes = (mergeProductionToNodes model.nodes producers)
                      }
                    , Cmd.none
                    )

                Err error ->
                    Debug.crash error
                        ( { model | isLoading = model.isLoading - 1 }, Cmd.none )

        ReceiveSettings raw ->
            case JD.decodeValue settingsDecoder raw of
                Ok settings ->
                    ( { model
                        | settings = settings
                        , settingsForm = settings
                        , isLoading = model.isLoading - 1
                        , editSettingsForm = False
                      }
                    , Cmd.none
                    )

                Err error ->
                    Debug.crash error
                        ( { model | isLoading = model.isLoading - 1 }, Cmd.none )

        ReceiveAlerts raw ->
            case JD.decodeValue alertsRowsDecoder raw of
                Ok alerts ->
                    ( { model
                        | alerts = alerts
                        , isLoading = model.isLoading - 1
                      }
                    , Cmd.none
                    )

                Err error ->
                    Debug.crash error
                        ( { model | isLoading = model.isLoading - 1 }, Cmd.none )

        ReceiveUpdateSettingsFail raw ->
            handleReceiveWsError model raw

        ReceiveUpsertNode raw ->
            case JD.decodeValue nodeDecoder raw of
                Ok node ->
                    let
                        nodes =
                            node
                                :: (model.nodes
                                        |> List.filter (\n -> n.account /= node.account)
                                   )
                    in
                        ( { model
                            | isLoading = model.isLoading - 1
                            , nodes = nodes
                            , showNode = False
                            , nodeForm = newNode
                            , viewingNode = Nothing
                            , showArchiveConfirmation = False
                          }
                        , Cmd.none
                        )

                Err error ->
                    Debug.crash error
                        ( { model | isLoading = model.isLoading - 1 }, Cmd.none )

        ReceiveUpsertNodeFail raw ->
            handleReceiveWsError model raw

        ReceiveArchiveRestoreFail raw ->
            handleReceiveWsError model raw

        ReceiveNodesFail raw ->
            handleReceiveWsError model raw

        ReceiveProducersFail raw ->
            handleReceiveWsError model raw

        ReceiveSettingsFail raw ->
            handleReceiveWsError model raw

        ReceiveMonitorState raw ->
            case JD.decodeValue monitorStateDecoder raw of
                Ok state ->
                    ( { model
                        | monitorState = state
                        , isLoading = model.isLoading - 1
                      }
                    , Cmd.none
                    )

                Err error ->
                    Debug.crash error
                        ( { model | isLoading = model.isLoading - 1 }, Cmd.none )

        ReceiveNode raw ->
            case JD.decodeValue nodeDecoder raw of
                Ok node ->
                    let
                        nodeExists =
                            (model.nodes
                                |> List.filter (\p -> p.account == node.account)
                                |> List.length
                            )
                                > 0

                        nodes =
                            if nodeExists then
                                model.nodes
                                    |> List.map
                                        (\n ->
                                            if n.account == node.account then
                                                node
                                            else
                                                n
                                        )
                            else
                                model.nodes ++ [ node ]
                    in
                        ( { model | nodes = nodes }, Cmd.none )

                Err error ->
                    Debug.crash error
                        ( model, Cmd.none )

        ReceiveAlert raw ->
            case JD.decodeValue alertDecoder raw of
                Ok alert ->
                    let
                        alerts =
                            alert :: model.alerts

                        notifications =
                            Notification (Error alert.description) model.currentTime (toString alert.createdAt)
                                :: model.notifications
                    in
                        ( { model | alerts = alerts, notifications = notifications }, (audioCmd model.isMuted) )

                Err error ->
                    let
                        test =
                            Debug.crash (error)
                    in
                        ( model, Cmd.none )

        ReceiveProducer raw ->
            case JD.decodeValue producerDecoder raw of
                Ok producer ->
                    let
                        producerExists =
                            (model.producers
                                |> List.filter (\p -> p.account == producer.account)
                                |> List.length
                            )
                                > 0

                        producers =
                            if producerExists then
                                model.producers
                                    |> List.map
                                        (\p ->
                                            if p.account == producer.account then
                                                producer
                                            else
                                                p
                                        )
                            else
                                model.producers ++ [ producer ]
                    in
                        ( { model
                            | producers = producers
                            , currentProducer = Just producer.account
                          }
                        , Cmd.none
                        )

                Err error ->
                    Debug.crash error
                        ( model, Cmd.none )

        Tick time ->
            let
                -- erase after 10 secs
                notifications =
                    model.notifications
                        |> List.filter
                            (\notification ->
                                (model.currentTime - notification.time) < 10000
                            )
            in
                ( { model | currentTime = time, notifications = notifications }, Cmd.none )

        DeleteNotification id ->
            let
                notifications =
                    model.notifications
                        |> List.filter (\notification -> notification.id /= id)
            in
                ( { model | notifications = notifications }, Cmd.none )

        SetContent content ->
            ( { model | content = content }, Cmd.none )

        ToggleNodeChainInfoModal n ->
            case n of
                Just node ->
                    let
                        newModel =
                            { model | viewingNode = Just node, isLoading = model.isLoading + 1, chainInfo = Nothing }

                        ( phxModel, cmdGetNodeChainInfo ) =
                            getNodeChainInfo newModel node.account
                    in
                        ( phxModel, cmdGetNodeChainInfo )

                Nothing ->
                    ( { model | viewingNode = Nothing, chainInfo = Nothing, showNodeChainInfo = False }, Cmd.none )

        ToggleHelp ->
            ( { model | showHelp = (not model.showHelp) }, Cmd.none )

        ToggleArchivedNodes ->
            ( { model | showArchivedNodes = (not model.showArchivedNodes) }, Cmd.none )

        ToggleAdminLoginModal ->
            ( { model
                | showAdminLogin = (not model.showAdminLogin)
                , adminPassword = ""
              }
            , Cmd.none
            )

        UpdateAdminLoginPassword str ->
            ( { model | adminPassword = str }, Cmd.none )

        SubmitAdminLogin ->
            ( { model | isLoading = model.isLoading + 1 }
            , submitAdminLogin model
            )

        AuthResponse (Ok user) ->
            ( { model
                | isLoading = model.isLoading - 1
                , user = user
                , showAdminLogin = False
                , adminPassword = ""
              }
            , signedIn (userEncoder user)
            )

        AuthResponse (Err err) ->
            let
                error =
                    Debug.log ">>>error"
                        err

                notifications =
                    Notification (Error "Admin Login Failed") model.currentTime "adminLoginFailed"
                        :: model.notifications
            in
                ( { model
                    | isLoading = model.isLoading - 1
                    , notifications = notifications
                  }
                , Cmd.none
                )

        ToggleNodeModal node ->
            case node of
                Just n ->
                    ( { model | showNode = True, nodeForm = n }, Cmd.none )

                Nothing ->
                    ( { model | showNode = False }, Cmd.none )

        ToggleSound ->
            ( { model | isMuted = (not model.isMuted) }, Cmd.none )

        Logout ->
            ( { model | user = User "" "" 0 }, signOut () )

        ToggleSettingsForm ->
            ( { model
                | settingsForm = model.settings
                , editSettingsForm = (not model.editSettingsForm)
              }
            , Cmd.none
            )

        UpdateSettingsFormPrincipalNode str ->
            let
                settingsForm =
                    model.settingsForm

                newSettings =
                    { settingsForm | principalNode = str }
            in
                ( { model | settingsForm = newSettings }, Cmd.none )

        UpdateSettingsFormMonitorLoopInterval str ->
            let
                settingsForm =
                    model.settingsForm

                num =
                    Result.withDefault settingsForm.monitorLoopInterval (String.toInt str)

                newSettings =
                    { settingsForm | monitorLoopInterval = num }
            in
                ( { model | settingsForm = newSettings }, Cmd.none )

        UpdateSettingsFormNodeLoopInterval str ->
            let
                settingsForm =
                    model.settingsForm

                num =
                    Result.withDefault settingsForm.nodeLoopInterval (String.toInt str)

                newSettings =
                    { settingsForm | nodeLoopInterval = num }
            in
                ( { model | settingsForm = newSettings }, Cmd.none )

        UpdateSettingsFormCalcVotesIntervalSecs str ->
            let
                settingsForm =
                    model.settingsForm

                num =
                    Result.withDefault settingsForm.calcVotesIntervalSecs (String.toInt str)

                newSettings =
                    { settingsForm | calcVotesIntervalSecs = num }
            in
                ( { model | settingsForm = newSettings }, Cmd.none )

        UpdateSettingsFormSameAlertIntervalMins str ->
            let
                settingsForm =
                    model.settingsForm

                num =
                    Result.withDefault settingsForm.sameAlertIntervalMins (String.toInt str)

                newSettings =
                    { settingsForm | sameAlertIntervalMins = num }
            in
                ( { model | settingsForm = newSettings }, Cmd.none )

        UpdateSettingsFormBpToleranceTimeSecs str ->
            let
                settingsForm =
                    model.settingsForm

                num =
                    Result.withDefault settingsForm.bpToleranceTimeSecs (String.toInt str)

                newSettings =
                    { settingsForm | bpToleranceTimeSecs = num }
            in
                ( { model | settingsForm = newSettings }, Cmd.none )

        UpdateSettingsFormUnsynchedBlocksToAlert str ->
            let
                settingsForm =
                    model.settingsForm

                num =
                    Result.withDefault settingsForm.unsynchedBlocksToAlert (String.toInt str)

                newSettings =
                    { settingsForm | unsynchedBlocksToAlert = num }
            in
                ( { model | settingsForm = newSettings }, Cmd.none )

        UpdateSettingsFormFailedPingsToAlert str ->
            let
                settingsForm =
                    model.settingsForm

                num =
                    Result.withDefault settingsForm.failedPingsToAlert (String.toInt str)

                newSettings =
                    { settingsForm | failedPingsToAlert = num }
            in
                ( { model | settingsForm = newSettings }, Cmd.none )

        SubmitSettings ->
            let
                ( newModel, cmd ) =
                    submitSettings model
            in
                ( { newModel | isLoading = (model.isLoading + 1) }, cmd )

        UpdateNodeFormAccount str ->
            let
                newForm =
                    model.nodeForm

                newObj =
                    { newForm | account = str }
            in
                ( { model | nodeForm = newObj }, Cmd.none )

        UpdateNodeFormIp str ->
            let
                newForm =
                    model.nodeForm

                newObj =
                    { newForm | ip = str }
            in
                ( { model | nodeForm = newObj }, Cmd.none )

        UpdateNodeFormPort str ->
            let
                newForm =
                    model.nodeForm

                num =
                    Result.withDefault newForm.addrPort (String.toInt str)

                newObj =
                    { newForm | addrPort = num }
            in
                ( { model | nodeForm = newObj }, Cmd.none )

        UpdateNodeFormType str ->
            let
                newForm =
                    model.nodeForm

                newObj =
                    { newForm | nodeType = (nodeTypeFromTxt str) }
            in
                ( { model | nodeForm = newObj }, Cmd.none )

        SubmitNode ->
            let
                ( newModel, cmd ) =
                    submitNode model
            in
                ( { newModel | isLoading = (model.isLoading + 1) }, cmd )

        ShowArchiveConfirmationModal node ->
            ( { model | viewingNode = Just node, showArchiveConfirmation = True }
            , Cmd.none
            )

        CancelArchive ->
            ( { model | viewingNode = Nothing, showArchiveConfirmation = False }
            , Cmd.none
            )

        SubmitArchive node ->
            let
                ( newModel, cmd ) =
                    submitArchive model node True
            in
                ( { newModel | isLoading = (model.isLoading + 1) }, cmd )

        NoOp ->
            ( model, Cmd.none )

        NoOpStr _ ->
            ( model, Cmd.none )



-- Functions


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


audioCmd : Bool -> Cmd Msg
audioCmd isMuted =
    if isMuted then
        Cmd.none
    else
        playSound ()


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

        Err error ->
            Debug.crash error
                ( { model | isLoading = model.isLoading - 1 }, Cmd.none )


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


isoStringToDateDecoder : JD.Decoder Float
isoStringToDateDecoder =
    JD.string
        |> JD.andThen
            (\val ->
                let
                    utcStr =
                        val ++ "Z"
                in
                    case Date.fromString utcStr of
                        Ok date ->
                            JD.succeed (toFloat (Core.toTime date))

                        Err _ ->
                            JD.succeed 0
            )


accountEncoder : String -> JE.Value
accountEncoder account =
    JE.object
        [ ( "account", JE.string account )
        ]


wsErrorDecoder : JD.Decoder String
wsErrorDecoder =
    JD.at [ "error" ] JD.string


statsDecoder : JD.Decoder MonitorState
statsDecoder =
    JD.map2
        MonitorState
        (JD.field "status" monitorStatusDecoder)
        (JD.field "last_block" JD.int)


userDecoder : JD.Decoder User
userDecoder =
    JDP.decode
        User
        |> JDP.required "user" JD.string
        |> JDP.required "token" JD.string
        |> JDP.hardcoded 0.0


chainInfoDataDecoder : JD.Decoder ChainInfoData
chainInfoDataDecoder =
    JDP.decode
        ChainInfoData
        |> JDP.optional "chain_info"
            chainInfoDecoder
            (ChainInfo "" "" 0 0 "" "" 0 "" 0 0 0 0)


chainInfoDecoder : JD.Decoder ChainInfo
chainInfoDecoder =
    JDP.decode
        ChainInfo
        |> JDP.required "server_version" JD.string
        |> JDP.required "chain_id" JD.string
        |> JDP.required "head_block_num" JD.int
        |> JDP.required "last_irreversible_block_num" JD.int
        |> JDP.required "last_irreversible_block_id" JD.string
        |> JDP.required "head_block_id" JD.string
        |> JDP.required "head_block_time" isoStringToDateDecoder
        |> JDP.required "head_block_producer" JD.string
        |> JDP.required "virtual_block_cpu_limit" JD.int
        |> JDP.required "virtual_block_net_limit" JD.int
        |> JDP.required "block_cpu_limit" JD.int
        |> JDP.required "block_net_limit" JD.int


userEncoder : User -> JE.Value
userEncoder obj =
    JE.object
        [ ( "userName", JE.string obj.userName )
        , ( "token", JE.string obj.token )
        , ( "expiration", JE.float obj.expiration )
        ]


alertsRowsDecoder : JD.Decoder (List Alert)
alertsRowsDecoder =
    JD.at [ "rows" ] (JD.list alertDecoder)


alertDecoder : JD.Decoder Alert
alertDecoder =
    let
        toDecoder alertType description createdAt =
            JD.succeed (Alert alertType description (createdAt / 1000000))
    in
        JDP.decode toDecoder
            |> JDP.required "type" JD.string
            |> JDP.required "description" JD.string
            |> JDP.required "created_at" JD.float
            |> JDP.resolve


nodeEncoder : Node -> String -> JE.Value
nodeEncoder obj token =
    JE.object
        [ ( "account", JE.string obj.account )
        , ( "token", JE.string token )
        , ( "ip", JE.string obj.ip )
        , ( "port", JE.int obj.addrPort )
        , ( "is_ssl", JE.bool obj.isSsl )
        , ( "is_watchable", JE.bool obj.isWatchable )
        , ( "type", JE.string (nodeTypeTxt obj.nodeType) )
        , ( "is_archived", JE.bool obj.isArchived )
        ]


nodeArchiveEncoder : String -> String -> Bool -> JE.Value
nodeArchiveEncoder token account isArchived =
    JE.object
        [ ( "account", JE.string account )
        , ( "token", JE.string token )
        , ( "is_archived", JE.bool isArchived )
        ]


nodeStatusDecoder : JD.Decoder NodeStatus
nodeStatusDecoder =
    JD.string
        |> JD.andThen
            (\string ->
                case string of
                    "initial" ->
                        JD.succeed Initial

                    "active" ->
                        JD.succeed Online

                    "unsynched_blocks" ->
                        JD.succeed UnsynchedBlocks

                    _ ->
                        JD.succeed Offline
            )


nodeTypeFromTxt : String -> NodeType
nodeTypeFromTxt str =
    if str == "BP" then
        BlockProducer
    else if str == "FN" then
        FullNode
    else
        ExternalBlockProducer


nodeTypeDecoder : JD.Decoder NodeType
nodeTypeDecoder =
    JD.string
        |> JD.andThen
            (\string ->
                case string of
                    "BP" ->
                        JD.succeed BlockProducer

                    "FN" ->
                        JD.succeed FullNode

                    _ ->
                        JD.succeed ExternalBlockProducer
            )


nodeDecoder : JD.Decoder Node
nodeDecoder =
    JDP.decode Node
        |> JDP.required "account" JD.string
        |> JDP.required "ip" JD.string
        |> JDP.required "port" JD.int
        |> JDP.required "is_ssl" JD.bool
        |> JDP.required "is_watchable" JD.bool
        |> JDP.optional "status" nodeStatusDecoder Initial
        |> JDP.optional "ping_ms" JD.int -1
        |> JDP.optional "head_block_num" JD.int -1
        |> JDP.optional "last_success_ping_at" JD.float -1
        |> JDP.optional "last_produced_block" JD.int 0
        |> JDP.optional "last_produced_block_at" isoStringToDateDecoder 0
        |> JDP.required "type" nodeTypeDecoder
        |> JDP.optional "vote_percentage" JD.float 0.0
        |> JDP.optional "is_archived" JD.bool False
        |> JDP.hardcoded False


nodesRowsDecoder : JD.Decoder (List Node)
nodesRowsDecoder =
    JD.at [ "rows" ] (JD.list nodeDecoder)


nodesDecoder : JD.Decoder (List Node)
nodesDecoder =
    JD.list nodeDecoder


producersRowsDecoder : JD.Decoder (List Producer)
producersRowsDecoder =
    JD.at [ "rows" ] (JD.list producerDecoder)


producersDecoder : JD.Decoder (List Producer)
producersDecoder =
    JD.list producerDecoder


producerDecoder : JD.Decoder Producer
producerDecoder =
    JDP.decode Producer
        |> JDP.required "account" JD.string
        |> JDP.required "last_produced_block" JD.int
        |> JDP.optional "last_produced_block_at" isoStringToDateDecoder 0
        |> JDP.required "blocks" JD.int
        |> JDP.required "transactions" JD.int


mergeProductionToNodes : List Node -> List Producer -> List Node
mergeProductionToNodes nodes producers =
    let
        mergeNode node =
            let
                producer =
                    producers
                        |> List.filter (\prd -> prd.account == node.account)
                        |> List.head
            in
                case producer of
                    Just p ->
                        { node
                            | lastProducedBlock = p.lastProducedBlock
                            , lastProducedBlockAt = p.lastProducedBlockAt
                        }

                    Nothing ->
                        node
    in
        nodes
            |> List.map
                (\node ->
                    case node.nodeType of
                        BlockProducer ->
                            mergeNode node

                        ExternalBlockProducer ->
                            mergeNode node

                        FullNode ->
                            node
                )


monitorStatusDecoder : JD.Decoder MonitorStatus
monitorStatusDecoder =
    JD.string
        |> JD.andThen
            (\string ->
                case string of
                    "initial" ->
                        JD.succeed InitialMonitor

                    "active" ->
                        JD.succeed Active

                    "syncing" ->
                        JD.succeed Syncing

                    _ ->
                        JD.succeed InitialMonitor
            )


monitorStateDecoder : JD.Decoder MonitorState
monitorStateDecoder =
    JDP.decode MonitorState
        |> JDP.required "status" monitorStatusDecoder
        |> JDP.hardcoded 0


settingsDecoder : JD.Decoder Settings
settingsDecoder =
    JDP.decode Settings
        |> JDP.optional "principal_node" JD.string ""
        |> JDP.required "monitor_loop_interval" JD.int
        |> JDP.required "node_loop_interval" JD.int
        |> JDP.required "same_alert_interval_mins" JD.int
        |> JDP.required "bp_tolerance_time_secs" JD.int
        |> JDP.required "unsynched_blocks_to_alert" JD.int
        |> JDP.required "failed_pings_to_alert" JD.int
        |> JDP.required "calc_votes_interval_secs" JD.int


settingsEncoder : Settings -> String -> JE.Value
settingsEncoder settings token =
    JE.object
        [ ( "token", JE.string token )
        , ( "principal_node", JE.string settings.principalNode )
        , ( "monitor_loop_interval", JE.int settings.monitorLoopInterval )
        , ( "node_loop_interval", JE.int settings.nodeLoopInterval )
        , ( "same_alert_interval_mins", JE.int settings.sameAlertIntervalMins )
        , ( "bp_tolerance_time_secs", JE.int settings.bpToleranceTimeSecs )
        , ( "unsynched_blocks_to_alert", JE.int settings.unsynchedBlocksToAlert )
        , ( "failed_pings_to_alert", JE.int settings.failedPingsToAlert )
        , ( "calc_votes_interval_secs", JE.int settings.calcVotesIntervalSecs )
        ]


nodeAddressLink : Node -> String
nodeAddressLink node =
    let
        prefix =
            if node.isSsl then
                "https://"
            else
                "http://"
    in
        prefix ++ node.ip ++ ":" ++ toString node.addrPort ++ "/v1/chain/get_info"


nodeAddress : Node -> String
nodeAddress node =
    node.ip ++ ":" ++ toString node.addrPort


nodeTypeTxt : NodeType -> String
nodeTypeTxt nodeType =
    case nodeType of
        BlockProducer ->
            "BP"

        FullNode ->
            "FN"

        ExternalBlockProducer ->
            "EBP"

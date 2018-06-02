port module Update exposing (..)

import Model exposing (..)
import Handlers exposing (..)
import Decoders exposing (..)
import Time
import Phoenix.Socket
import Json.Decode as JD


-- Ports and Subscriptions


port signOut : () -> Cmd msg


port signedIn : JD.Value -> Cmd msg


port playSound : () -> Cmd msg


audioCmd : Bool -> Cmd Msg
audioCmd isMuted =
    if isMuted then
        Cmd.none
    else
        playSound ()


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
    , showRestoreConfirmation = False
    , showNodeChainInfo = False
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

                        sortedNodes =
                            nodes |> List.sortBy .position
                    in
                        ( { model | nodes = sortedNodes }, Cmd.none )

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

        UpdateNodeFormIsWatchable ->
            let
                newForm =
                    model.nodeForm

                newObj =
                    { newForm | isWatchable = not newForm.isWatchable }
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

        UpdateNodeFormPosition str ->
            let
                newForm =
                    model.nodeForm

                num =
                    Result.withDefault newForm.position (String.toInt str)

                newObj =
                    { newForm | position = num }
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

        ShowRestoreConfirmationModal node ->
            ( { model | viewingNode = Just node, showRestoreConfirmation = True }
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

        CancelRestore ->
            ( { model | viewingNode = Nothing, showRestoreConfirmation = False }
            , Cmd.none
            )

        SubmitRestore node ->
            let
                ( newModel, cmd ) =
                    submitArchive model node False
            in
                ( { newModel | isLoading = (model.isLoading + 1) }, cmd )

        NoOp ->
            ( model, Cmd.none )

        NoOpStr _ ->
            ( model, Cmd.none )

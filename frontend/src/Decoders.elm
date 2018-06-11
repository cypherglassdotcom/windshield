module Decoders exposing (..)

import Utils exposing (..)
import Json.Encode as JE
import Json.Decode as JD
import Json.Decode.Pipeline as JDP
import Date
import Date.Extra.Core as Core
import Model exposing (..)


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


statsDecoder : JD.Decoder MonitorStats
statsDecoder =
    JD.map2
        MonitorStats
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
        , ( "position", JE.int obj.position )
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
        |> JDP.optional "vote_position" JD.int 9999
        |> JDP.optional "is_archived" JD.bool False
        |> JDP.optional "position" JD.int 999
        |> JDP.optional "bp_paused" JD.bool False
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
        |> JDP.required "version" JD.string


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

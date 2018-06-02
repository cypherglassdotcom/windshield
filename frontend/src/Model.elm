module Model exposing (..)

import Time
import Phoenix.Socket
import Json.Encode as JE
import Http


-- Model


type NotificationType
    = Success String
    | Warning String
    | Error String


type Content
    = Home
    | Alerts
    | SettingsView


type NodeStatus
    = Initial
    | Online
    | Offline
    | UnsynchedBlocks


type MonitorStatus
    = InitialMonitor
    | Active
    | Syncing


type NodeType
    = BlockProducer
    | FullNode
    | ExternalBlockProducer


type alias Flags =
    { user : User
    , socketServer : String
    , backendServer : String
    }


type alias User =
    { userName : String
    , token : String
    , expiration : Time.Time
    }


type alias MonitorState =
    { status : MonitorStatus
    , lastBlockNum : Int
    }


type alias Alert =
    { alertType : String
    , description : String
    , createdAt : Time.Time
    }


type alias Producer =
    { account : String
    , lastProducedBlock : Int
    , lastProducedBlockAt : Time.Time
    , blocks : Int
    , transactions : Int
    }


type alias Node =
    { account : String
    , ip : String
    , addrPort : Int
    , isSsl : Bool
    , isWatchable : Bool
    , status : NodeStatus
    , pingMs : Int
    , headBlockNum : Int
    , lastSuccessPingAt : Time.Time
    , lastProducedBlock : Int
    , lastProducedBlockAt : Time.Time
    , nodeType : NodeType
    , votePercentage : Float
    , isArchived : Bool
    , isNew : Bool
    }


type alias ChainInfoData =
    { chainInfo : ChainInfo }


type alias ChainInfo =
    { serverVersion : String
    , chainId : String
    , headBlockNum : Int
    , lastIrreversibleBlockNum : Int
    , lastIrreversibleBlockId : String
    , headBlockId : String
    , headBlockTime : Time.Time
    , headBlockProducer : String
    , virtualBlockCpuLimit : Int
    , virtualBlockNetLimit : Int
    , blockCpuLimit : Int
    , blockNetLimit : Int
    }


type alias Notification =
    { notification : NotificationType
    , time : Time.Time
    , id : String
    }


type alias Settings =
    { principalNode : String
    , monitorLoopInterval : Int
    , nodeLoopInterval : Int
    , sameAlertIntervalMins : Int
    , bpToleranceTimeSecs : Int
    , unsynchedBlocksToAlert : Int
    , failedPingsToAlert : Int
    , calcVotesIntervalSecs : Int
    }


type alias Model =
    { isLoading : Int
    , isMuted : Bool
    , showHelp : Bool
    , showNode : Bool
    , showArchivedNodes : Bool
    , showAdminLogin : Bool
    , showArchiveConfirmation : Bool
    , adminPassword : String
    , user : User
    , socketServer : String
    , backendServer : String
    , content : Content
    , socketsConnected : Bool
    , currentTime : Time.Time
    , notifications : List Notification
    , producers : List Producer
    , nodes : List Node
    , currentProducer : Maybe String
    , phxSocket : Phoenix.Socket.Socket Msg
    , monitorConnected : Bool
    , monitorState : MonitorState
    , principalNode : String
    , settings : Settings
    , settingsForm : Settings
    , editSettingsForm : Bool
    , nodeForm : Node
    , chainInfo : Maybe ChainInfo
    , viewingNode : Maybe Node
    , showNodeChainInfo : Bool
    , alerts : List Alert
    }


newNode : Node
newNode =
    Node "" "" 8888 False True Initial 0 0 0.0 0 0.0 BlockProducer 0.0 False True


type Msg
    = Tick Time.Time
    | SetContent Content
    | ToggleHelp
    | ToggleSound
    | DeleteNotification String
    | Logout
    | PhoenixMsg (Phoenix.Socket.Msg Msg)
    | JoinChannel
    | ShowJoinedMessage String
    | ShowLeftMessage String
    | ReceiveTickStats JE.Value
    | ReceiveMonitorState JE.Value
    | ReceiveAlert JE.Value
    | ReceiveNode JE.Value
    | ReceiveNodes JE.Value
    | ReceiveAlerts JE.Value
    | ReceiveNodesFail JE.Value
    | ReceiveProducers JE.Value
    | ReceiveProducersFail JE.Value
    | ReceiveSettings JE.Value
    | ReceiveSettingsFail JE.Value
    | ReceiveProducer JE.Value
    | ReceiveUpdateSettingsFail JE.Value
    | ReceiveUpsertNode JE.Value
    | ReceiveNodeChainInfo JE.Value
    | ReceiveUpsertNodeFail JE.Value
    | ReceiveArchiveRestoreFail JE.Value
    | ToggleSettingsForm
    | UpdateSettingsFormPrincipalNode String
    | UpdateSettingsFormMonitorLoopInterval String
    | UpdateSettingsFormNodeLoopInterval String
    | UpdateSettingsFormCalcVotesIntervalSecs String
    | UpdateSettingsFormSameAlertIntervalMins String
    | UpdateSettingsFormBpToleranceTimeSecs String
    | UpdateSettingsFormUnsynchedBlocksToAlert String
    | UpdateSettingsFormFailedPingsToAlert String
    | SubmitSettings
    | ToggleAdminLoginModal
    | SubmitAdminLogin
    | UpdateAdminLoginPassword String
    | ToggleNodeChainInfoModal (Maybe Node)
    | ToggleNodeModal (Maybe Node)
    | ToggleArchivedNodes
    | AuthResponse (Result Http.Error User)
    | UpdateNodeFormAccount String
    | UpdateNodeFormIp String
    | UpdateNodeFormPort String
    | UpdateNodeFormType String
    | SubmitNode
    | ShowArchiveConfirmationModal Node
    | CancelArchive
    | SubmitArchive Node
    | NoOp
    | NoOpStr String

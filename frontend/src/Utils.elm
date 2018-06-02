module Utils exposing (..)

import Model exposing (..)
import Date.Extra.Format as DateFormat
import Date.Extra.Config.Config_en_us as DateConfig
import Date.Distance as Distance
import FormatNumber exposing (format)
import FormatNumber.Locales exposing (usLocale)
import Time
import Date


calcTimeDiff : Time.Time -> Time.Time -> String
calcTimeDiff timeOld timeNew =
    let
        defaultConfig =
            Distance.defaultConfig

        config =
            { defaultConfig | includeSeconds = True }

        inWords =
            config
                |> Distance.inWordsWithConfig

        dateOld =
            Date.fromTime timeOld

        dateNew =
            Date.fromTime timeNew
    in
        inWords dateOld dateNew


formatPercentage : Float -> String
formatPercentage num =
    (format usLocale (num * 100)) ++ "%"


formatTime : Time.Time -> String
formatTime time =
    if time > 0 then
        time
            |> Date.fromTime
            |> DateFormat.format DateConfig.config
                "%m/%d/%Y %H:%M:%S"
    else
        "--"


reversedComparison : comparable -> comparable -> Order
reversedComparison a b =
    case compare a b of
        LT ->
            GT

        EQ ->
            EQ

        GT ->
            LT


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

port module Components exposing (..)

import Html exposing (..)
import Html.Attributes exposing (attribute, class, defaultValue, href, placeholder, target, type_, value, src, colspan)
import Html.Events exposing (onClick, onInput, onWithOptions)
import Model exposing (Msg(NoOpStr))


columns : Bool -> List (Html msg) -> Html msg
columns isMultiline cols =
    let
        mlClass =
            if isMultiline then
                " is-multiline"
            else
                ""
    in
        div [ class ("columns" ++ mlClass) ]
            (cols
                |> List.map (\item -> div [ class "column" ] [ item ])
            )


titleMenu : String -> List (Html msg) -> Html msg
titleMenu title menu =
    div [ class "level" ]
        [ div [ class "level-left" ]
            [ div [ class "level-item" ] [ h2 [] [ text title ] ] ]
        , div [ class "level-right" ]
            (menu
                |> List.map (\item -> div [ class "level-item" ] [ item ])
            )
        ]


icon : String -> Bool -> Bool -> Html msg
icon icon spin isLeft =
    let
        spinner =
            if spin then
                " fa-spin"
            else
                ""

        className =
            "fa" ++ spinner ++ " fa-" ++ icon

        classIcon =
            if isLeft then
                "icon is-left"
            else
                "icon"
    in
        span [ class classIcon ]
            [ i [ class className ]
                []
            ]


loadingIcon : Int -> Html msg
loadingIcon isLoading =
    if isLoading > 0 then
        icon "circle-o-notch" True False
    else
        text ""


disabledAttribute : Bool -> Attribute msg
disabledAttribute isDisabled =
    if isDisabled then
        attribute "disabled" "true"
    else
        attribute "data-empty" ""


formFooter : msg -> msg -> Html msg
formFooter submit cancel =
    div [ class "field is-grouped is-grouped-right" ]
        [ p [ class "control" ]
            [ a [ class "button is-primary", onClick submit ]
                [ text "Submit" ]
            ]
        , p [ class "control" ]
            [ a [ class "button is-light", onClick cancel ]
                [ text "Cancel" ]
            ]
        ]


basicFieldInput : Int -> String -> String -> String -> String -> (String -> msg) -> Bool -> String -> Html msg
basicFieldInput isLoading fieldLabel fieldValue fieldPlaceHolder fieldIcon fieldMsg readOnly fieldType =
    let
        loadingClass =
            if isLoading > 0 then
                " is-loading"
            else
                ""

        field =
            if readOnly then
                div [ class ("field-read") ] [ text fieldValue ]
            else
                div
                    [ class
                        ("control has-icons-left has-icons-right"
                            ++ loadingClass
                        )
                    ]
                    [ input
                        [ class "input"
                        , placeholder fieldPlaceHolder
                        , type_ fieldType
                        , defaultValue fieldValue
                        , onInput fieldMsg
                        , disabledAttribute (isLoading > 0)
                        ]
                        []
                    , icon fieldIcon False True
                    ]
    in
        div [ class "field" ]
            [ label [ class "label" ]
                [ text fieldLabel ]
            , field
            ]


fieldInput : Int -> String -> String -> String -> String -> (String -> msg) -> Bool -> Html msg
fieldInput isLoading fieldLabel fieldValue fieldPlaceHolder fieldIcon fieldMsg readOnly =
    basicFieldInput isLoading fieldLabel fieldValue fieldPlaceHolder fieldIcon fieldMsg readOnly "text"


displayField : String -> String -> String -> Html Msg
displayField fieldLabel fieldValue fieldIcon =
    basicFieldInput 0 fieldLabel fieldValue "" fieldIcon NoOpStr True "text"


passwordInput : Int -> String -> String -> String -> String -> (String -> msg) -> Bool -> Html msg
passwordInput isLoading fieldLabel fieldValue fieldPlaceHolder fieldIcon fieldMsg readOnly =
    basicFieldInput isLoading fieldLabel fieldValue fieldPlaceHolder fieldIcon fieldMsg readOnly "password"


selectInput : Int -> List ( String, String ) -> String -> String -> String -> (String -> msg) -> Html msg
selectInput isLoading optionsType fieldLabel fieldValue fieldIcon fieldMsg =
    let
        options =
            optionsType
                |> List.map
                    (\( optVal, optText ) ->
                        let
                            selectedAttr =
                                if optVal == fieldValue then
                                    [ value optVal
                                    , attribute "selected" ""
                                    ]
                                else
                                    [ value optVal ]
                        in
                            option
                                selectedAttr
                                [ text optText ]
                    )

        loadingClass =
            if isLoading > 0 then
                " is-loading"
            else
                ""
    in
        div [ class "field" ]
            [ label [ class "label" ]
                [ text fieldLabel ]
            , div [ class ("control has-icons-left" ++ loadingClass) ]
                [ div [ class "select is-fullwidth" ]
                    [ select
                        [ onInput fieldMsg
                        , defaultValue fieldValue
                        , disabledAttribute (isLoading > 0)
                        ]
                        options
                    ]
                , icon fieldIcon False True
                ]
            ]


checkBoxInput : Int -> String -> String -> Bool -> msg -> Bool -> Html msg
checkBoxInput isLoading fieldLabel fieldPlaceHolder isChecked checkMsg readOnly =
    let
        loadingClass =
            if isLoading > 0 then
                " is-loading"
            else
                ""

        ( valueTxt, inputClass ) =
            if isChecked then
                ( "On", " is-success" )
            else
                ( "Off", " is-danger" )

        checkTag =
            div [ class ("tags has-addons" ++ loadingClass) ]
                [ span [ class ("tag is-medium" ++ inputClass) ]
                    [ text valueTxt ]
                , span [ class "tag is-medium" ]
                    [ text fieldPlaceHolder ]
                ]

        content =
            if isLoading == 0 && not readOnly then
                a [ onClick checkMsg ] [ checkTag ]
            else
                checkTag
    in
        div [ class "field" ]
            [ label [ class "label" ]
                [ text fieldLabel ]
            , content
            ]


modalCard : Int -> String -> msg -> List (Html msg) -> Maybe ( String, msg ) -> Maybe ( String, msg ) -> Html msg
modalCard isLoading title close body ok cancel =
    let
        loadingClass =
            if isLoading > 0 then
                " is-loading"
            else
                ""

        okButton =
            case ok of
                Just ( txt, msg ) ->
                    button
                        [ class ("button is-success" ++ loadingClass)
                        , onClick msg
                        , disabledAttribute (isLoading > 0)
                        ]
                        [ text txt ]

                Nothing ->
                    text ""

        cancelButton =
            case cancel of
                Just ( txt, msg ) ->
                    button
                        [ class ("button is-light" ++ loadingClass)
                        , onClick msg
                        , disabledAttribute (isLoading > 0)
                        ]
                        [ text txt ]

                Nothing ->
                    text ""
    in
        div [ class "modal is-active" ]
            [ div [ class "modal-background" ] []
            , div [ class "modal-card" ]
                [ header [ class "modal-card-head" ]
                    [ p [ class "modal-card-title" ]
                        [ text title ]
                    , button
                        [ class "delete"
                        , attribute "aria-label" "close"
                        , onClick close
                        ]
                        []
                    ]
                , section [ class "modal-card-body" ]
                    body
                , footer [ class "modal-card-foot" ]
                    [ okButton
                    , cancelButton
                    ]
                ]
            ]

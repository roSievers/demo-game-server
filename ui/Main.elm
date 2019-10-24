module Main exposing (main)

import Browser
import Browser.Navigation as Navigation
import Dict exposing (Dict)
import Element exposing (Attribute, Element, spacing)
import Element.Events as Events
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Icon as Icon exposing (Icon)
import FontAwesome.Solid as Solid
import FontAwesome.Styles
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import RemoteData exposing (WebData)
import Url exposing (Url)
import Url.Builder as Url
import Url.Parser as Parse exposing ((</>), Parser)


main : Program Value Model Msg
main =
    Browser.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , onUrlRequest = onUrlRequest
        , onUrlChange = onUrlChange
        }


type GameId
    = GameId Int


type Route
    = Dashboard
    | SingleGame GameId


type alias Model =
    { taco : Taco
    , usernameField : String
    , passwordField : String
    , newGameDescriptionField : String
    , changeGameDescription : Maybe String
    , gameHeaderCache : Dict Int (WebData GameHeader)
    , gameList : WebData (List GameId)
    , route : Route
    , friends : WebData (List UserInfo)
    }


type alias Taco =
    { username : Maybe String
    , navKey : Navigation.Key
    }


type Msg
    = NoOp
    | LoginSuccess String
    | LogoutSuccess
    | HttpError Http.Error
    | TypeUsername String
    | TypePassword String
      -- In the game creation dialog
    | TypeNewGameDescription String
      -- In the existing game, change the game description
    | TypeUpdateGameDescription String
    | SaveUpdateGameDescription GameId String
    | CancelUpdateGameDescription
    | TryLogin
    | Logout
    | LoadGameList
    | GameListSuccess (List GameHeader)
    | GameSuccess (Maybe GameHeader)
    | FriendListSuccess (List UserInfo)
    | OpenSingleGame GameId
    | OpenDashboard
    | ChangedUrl Url
    | CreateGame
    | GameCreated GameHeader
    | ReloadFriends
    | GameReload GameId
    | UpdateMemberAssignment GameId GameMember


init : Value -> Url -> Navigation.Key -> ( Model, Cmd Msg )
init flags url navKey =
    let
        identity =
            Decode.decodeValue decodeIdentity flags
                |> Result.withDefault Nothing

        taco =
            { username = identity, navKey = navKey }
    in
    { taco = taco
    , usernameField = ""
    , passwordField = ""
    , newGameDescriptionField = ""
    , changeGameDescription = Nothing
    , gameHeaderCache = Dict.empty
    , gameList = RemoteData.NotAsked
    , route = Dashboard -- Overwritten by initRoute
    , friends = RemoteData.NotAsked
    }
        |> initRoute url


initRoute : Url -> Model -> ( Model, Cmd Msg )
initRoute url model =
    let
        newRoute =
            Parse.parse route url
                |> Maybe.withDefault Dashboard
    in
    case newRoute of
        Dashboard ->
            ( { model | route = newRoute }, Cmd.none )

        SingleGame (GameId gameId) ->
            ( { model
                | route = newRoute
                , gameHeaderCache = Dict.insert gameId RemoteData.Loading model.gameHeaderCache
              }
            , loadGame (GameId gameId)
            )


view : Model -> Browser.Document Msg
view model =
    { title = "Demo Game Client"
    , body =
        [ FontAwesome.Styles.css
        , Element.layout [] <| document model
        ]
    }


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


onUrlRequest : Browser.UrlRequest -> Msg
onUrlRequest _ =
    NoOp


onUrlChange : Url -> Msg
onUrlChange url =
    ChangedUrl url



-------------------------------------------------------------------------------
------------------------------ Update function --------------------------------
-------------------------------------------------------------------------------


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        LoginSuccess username ->
            ( { model | taco = loginTaco username model.taco }, Cmd.none )

        HttpError error ->
            Debug.log "Http Error" (Debug.toString error) |> (\_ -> ( model, Cmd.none ))

        LogoutSuccess ->
            ( { model | taco = logoutTaco model.taco, gameList = RemoteData.NotAsked }, Cmd.none )

        TypeUsername rawInput ->
            ( { model | usernameField = rawInput }, Cmd.none )

        TypePassword rawInput ->
            ( { model | passwordField = rawInput }, Cmd.none )

        TryLogin ->
            ( model, login { username = model.usernameField, password = model.passwordField } )

        Logout ->
            ( model, logout )

        LoadGameList ->
            ( { model | gameList = RemoteData.Loading }, loadGameList )

        GameListSuccess gameList ->
            ( replaceReceivedGameList gameList model, Cmd.none )

        OpenSingleGame (GameId gameId) ->
            ( { model | route = SingleGame (GameId gameId) }
            , Navigation.pushUrl model.taco.navKey
                (Url.absolute [ "game", String.fromInt gameId ] [])
            )

        OpenDashboard ->
            ( { model | route = Dashboard }, Navigation.pushUrl model.taco.navKey "/" )

        ChangedUrl url ->
            case Parse.parse route url of
                Just newRoute ->
                    ( { model | route = newRoute }, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        TypeNewGameDescription rawString ->
            ( { model | newGameDescriptionField = rawString }, Cmd.none )

        CreateGame ->
            ( model, createGame model )

        GameCreated newGame ->
            ( appendReceivedGameList newGame model, Cmd.none )

        GameSuccess game ->
            case game of
                Just newGame ->
                    ( updateGameHeaderCache [ newGame ] model, Cmd.none )

                Nothing ->
                    ( model, Cmd.none )

        FriendListSuccess friends ->
            ( { model | friends = RemoteData.Success friends }, Cmd.none )

        ReloadFriends ->
            ( { model | friends = RemoteData.Loading }, loadFriendList )

        GameReload gameId ->
            ( model, loadGame gameId )

        TypeUpdateGameDescription rawString ->
            ( { model | changeGameDescription = Just rawString }, Cmd.none )

        SaveUpdateGameDescription gameId newDescription ->
            ( { model | changeGameDescription = Nothing }
            , postSetupMessage gameId (SetDescription newDescription)
            )

        CancelUpdateGameDescription ->
            ( { model | changeGameDescription = Nothing }, Cmd.none )

        UpdateMemberAssignment gameId gameMember ->
            ( model
            , postSetupMessage gameId (UpdateMember gameMember)
            )


appendReceivedGameList : GameHeader -> Model -> Model
appendReceivedGameList game model =
    let
        newGameList =
            case model.gameList of
                RemoteData.Success oldGameList ->
                    GameId game.id :: oldGameList

                _ ->
                    [ GameId game.id ]
    in
    { model | gameList = RemoteData.Success newGameList }
        |> updateGameHeaderCache [ game ]


replaceReceivedGameList : List GameHeader -> Model -> Model
replaceReceivedGameList games model =
    let
        newGameList =
            games |> List.map (\game -> GameId game.id)
    in
    { model | gameList = RemoteData.Success newGameList }
        |> updateGameHeaderCache games


updateGameHeaderCache : List GameHeader -> Model -> Model
updateGameHeaderCache games model =
    let
        asDict =
            games
                |> List.map (\game -> ( game.id, RemoteData.Success game ))
                |> Dict.fromList

        newCache =
            -- The order of the dicts is important. If there is a collision,
            -- preference is given to the first (newer) dictionary.
            Dict.union asDict model.gameHeaderCache
    in
    { model | gameHeaderCache = newCache }


singleGameRoute : Parser (GameId -> a) a
singleGameRoute =
    Parse.s "game"
        </> Parse.int
        |> Parse.map GameId


route : Parser (Route -> a) a
route =
    Parse.oneOf
        [ Parse.map Dashboard Parse.top
        , Parse.map SingleGame singleGameRoute
        ]



-------------------------------------------------------------------------------
--------------------- View function, written with elm-ui ----------------------
-------------------------------------------------------------------------------


document : Model -> Element Msg
document model =
    case model.route of
        Dashboard ->
            dashboard model

        SingleGame gameId ->
            singleGame model gameId


dashboard : Model -> Element Msg
dashboard model =
    Element.column [ spacing 15 ]
        [ loginInfo model
        , gameOverview model
        , gameCreationDialog model
        ]


gameOverview : Model -> Element Msg
gameOverview model =
    Element.column []
        [ Input.button [] { label = Element.text "List Games", onPress = Just LoadGameList }
        , gameOverviewStatus model
        ]


{-| Extract the list of games as GameHeaders from the model, so that the WebData
monad is wrapping it only once on the outside.
-}
gameHeaderList : Model -> WebData (List GameHeader)
gameHeaderList model =
    -- TODO: This is a high complexity function that needs a refactoring.
    RemoteData.andThen
        (List.map (\(GameId id) -> Dict.get id model.gameHeaderCache |> Maybe.withDefault RemoteData.NotAsked)
            >> RemoteData.fromList
        )
        model.gameList


gameOverviewStatus : Model -> Element Msg
gameOverviewStatus model =
    case gameHeaderList model of
        RemoteData.NotAsked ->
            Element.text "The game list was never requested."

        RemoteData.Loading ->
            Element.text "The game list is currently loading."

        RemoteData.Failure _ ->
            Element.text "An error occured while loading the game list."

        RemoteData.Success gameList ->
            gameOverviewTable gameList


loginInfo : Model -> Element Msg
loginInfo model =
    case model.taco.username of
        Nothing ->
            loginDialog model

        Just name ->
            loginMessage model name


loginDialog : Model -> Element Msg
loginDialog model =
    Element.column []
        [ Input.username []
            { label = Input.labelAbove [] (Element.text "Username")
            , onChange = TypeUsername
            , placeholder = Just (Input.placeholder [] (Element.text "Username"))
            , text = model.usernameField
            }
        , Input.currentPassword []
            { label = Input.labelAbove [] (Element.text "Password")
            , onChange = TypePassword
            , placeholder = Just (Input.placeholder [] (Element.text "Password"))
            , text = model.passwordField
            , show = False
            }
        , Input.button [] { label = Element.text "Login", onPress = Just TryLogin }
        ]


loginMessage : Model -> String -> Element Msg
loginMessage _ name =
    Element.column []
        [ Element.text ("Hello, " ++ name)
        , Input.button [] { label = Element.text "Logout", onPress = Just Logout }
        ]


gameOverviewTable : List GameHeader -> Element Msg
gameOverviewTable list =
    let
        idCol =
            { header = Element.text "id"
            , width = Element.fill
            , view = \game -> Element.text (String.fromInt game.id)
            }

        playerCol =
            { header = Element.text "players"
            , width = Element.fill
            , view =
                \game ->
                    game.members
                        |> List.map (\member -> member.username)
                        |> String.join ", "
                        |> Element.text
            }

        descriptionCol =
            { header = Element.text "description"
            , width = Element.fill
            , view = \game -> Element.el [ Events.onClick (OpenSingleGame (GameId game.id)) ] (Element.text game.description)
            }
    in
    Element.table []
        { data = list
        , columns = [ idCol, playerCol, descriptionCol ]
        }


gameCreationDialog : Model -> Element Msg
gameCreationDialog model =
    Element.column []
        [ Element.text "Create new game"
        , Input.text []
            { label = Input.labelAbove [] (Element.text "Game Description")
            , onChange = TypeNewGameDescription
            , placeholder = Just (Input.placeholder [] (Element.text "Name or short description"))
            , text = model.newGameDescriptionField
            }
        , Input.button [] { label = Element.text "Create Game", onPress = Just CreateGame }
        ]


singleGame : Model -> GameId -> Element Msg
singleGame model (GameId id) =
    let
        maybeGame =
            Dict.get id model.gameHeaderCache
                |> Maybe.withDefault RemoteData.NotAsked

        gameElement =
            case maybeGame of
                RemoteData.NotAsked ->
                    Element.text "Game not available. Try refreshing the page."

                RemoteData.Loading ->
                    Element.text "Loading game in progress..."

                RemoteData.Failure _ ->
                    Element.text "Error while loading game."

                RemoteData.Success game ->
                    gameDetailView model game
    in
    Element.column []
        [ Input.button [] { label = Element.text "Return to Dashboard", onPress = Just OpenDashboard }
        , gameElement
        ]


friendList : Model -> GameHeader -> Element Msg
friendList model game =
    Element.column []
        ([ Element.text "Invite friends to this game."
         , Input.button [] { label = Element.text "Refresh friends list", onPress = Just ReloadFriends }
         ]
            ++ friendListRemoteExtractor model game
        )


friendListRemoteExtractor : Model -> GameHeader -> List (Element Msg)
friendListRemoteExtractor model game =
    case model.friends of
        RemoteData.NotAsked ->
            [ Element.text "Please refresh your friends list" ]

        RemoteData.Loading ->
            [ Element.text "Friend list is currently loading" ]

        RemoteData.Failure _ ->
            [ Element.text "Error while loading friends list. Try refreshing." ]

        RemoteData.Success friends ->
            inviteList model game friends


inviteList : Model -> GameHeader -> List UserInfo -> List (Element Msg)
inviteList _ game friends =
    let
        notInvolved =
            friends
                |> List.filter (\userInfo -> not (userIsMember userInfo.id game))
    in
    if List.length notInvolved > 0 then
        List.map (inviteListEntry game) notInvolved

    else
        [ Element.text "All your friends are already in the game." ]


userIsMember : Int -> GameHeader -> Bool
userIsMember userId game =
    game.members
        |> List.any (\member -> member.id == userId)


inviteListEntry : GameHeader -> UserInfo -> Element Msg
inviteListEntry game userInfo =
    Element.row [ spacing 5 ]
        [ Element.text userInfo.username
        , inviteListEntryButton game userInfo WhitePlayer "Invite as White"
        , inviteListEntryButton game userInfo BlackPlayer "Invite as Black"
        , inviteListEntryButton game userInfo Watcher "Invite as Watcher"
        ]


inviteListEntryButton : GameHeader -> UserInfo -> MemberRole -> String -> Element Msg
inviteListEntryButton game userInfo role caption =
    let
        label =
            Element.row [ spacing 5 ]
                [ icon [] Solid.plus
                , Element.text caption
                ]

        gameMember =
            { id = userInfo.id
            , role = role
            , username = userInfo.username
            , accepted = False
            }
    in
    Input.button []
        { label = label
        , onPress = Just (UpdateMemberAssignment (GameId game.id) gameMember)
        }


gameDetailView : Model -> GameHeader -> Element Msg
gameDetailView model game =
    Element.column [ spacing 15 ]
        [ gameDescriptionView model game
        , memberTable game
        , friendList model game
        ]


gameDescriptionView : Model -> GameHeader -> Element Msg
gameDescriptionView model game =
    case model.changeGameDescription of
        Nothing ->
            Element.el
                [ Events.onClick (TypeUpdateGameDescription game.description)
                ]
                (Element.text game.description)

        Just newDescription ->
            Element.row [ spacing 5 ]
                [ Input.text []
                    { label = Input.labelHidden "Game Description"
                    , onChange = TypeUpdateGameDescription
                    , placeholder = Just (Input.placeholder [] (Element.text "Update the game description"))
                    , text = newDescription
                    }
                , icon [ Events.onClick (SaveUpdateGameDescription (GameId game.id) newDescription) ] Solid.check
                , icon [ Events.onClick CancelUpdateGameDescription ] Solid.times
                ]


memberTable : GameHeader -> Element Msg
memberTable game =
    let
        idCol =
            { header = Element.text "id"
            , width = Element.fill
            , view = \member -> Element.text (String.fromInt member.id)
            }

        nameCol =
            { header = Element.text "username"
            , width = Element.fill
            , view = \member -> Element.text member.username
            }

        roleCol =
            { header = Element.text "role"
            , width = Element.fill
            , view = \member -> roleTag member.role
            }
    in
    Element.table []
        { data = game.members
        , columns = [ idCol, nameCol, roleCol ]
        }


roleTag : MemberRole -> Element msg
roleTag role =
    case role of
        WhitePlayer ->
            Element.row []
                [ icon [ Font.color (Element.rgb 0.9 0.9 0.9) ] Solid.chessQueen
                , Element.text "WhitePlayer"
                ]

        BlackPlayer ->
            Element.row [] [ icon [] Solid.chessQueen, Element.text "BlackPlayer" ]

        Watcher ->
            Element.row [] [ icon [] Solid.eye, Element.text "Watcher" ]


icon : List (Attribute msg) -> Icon -> Element msg
icon attributes iconSvg =
    iconSvg
        |> Icon.present
        |> Icon.view
        |> Element.html
        |> Element.el attributes



-------------------------------------------------------------------------------
--------------------------- Http Api of the Server ----------------------------
-------------------------------------------------------------------------------


{-| Determines how a user is connected to a game.
-}
type MemberRole
    = WhitePlayer
    | BlackPlayer
    | Watcher


fromStringMemberRole : String -> Decoder MemberRole
fromStringMemberRole string =
    case string of
        "BlackPlayer" ->
            Decode.succeed BlackPlayer

        "Watcher" ->
            Decode.succeed Watcher

        "WhitePlayer" ->
            Decode.succeed WhitePlayer

        _ ->
            Decode.fail ("Not valid pattern for decoder to MemberRole. Pattern: " ++ string)


toStringMemberRole : MemberRole -> String
toStringMemberRole role =
    case role of
        WhitePlayer ->
            "WhitePlayer"

        BlackPlayer ->
            "BlackPlayer"

        Watcher ->
            "Watcher"


decodeMemberRole : Decoder MemberRole
decodeMemberRole =
    Decode.string
        |> Decode.andThen fromStringMemberRole


encodeMemberRole : MemberRole -> Value
encodeMemberRole role =
    Encode.string (toStringMemberRole role)


type alias LoginData =
    { username : String
    , password : String
    }


encodeLoginData : LoginData -> Value
encodeLoginData record =
    Encode.object
        [ ( "username", Encode.string <| record.username )
        , ( "password", Encode.string <| record.password )
        ]


decodeUserName : Decoder String
decodeUserName =
    Decode.field "identity" Decode.string


decodeIdentity : Decoder (Maybe String)
decodeIdentity =
    Decode.field "identity" (Decode.maybe Decode.string)


decodeLogout : Decoder ()
decodeLogout =
    Decode.field "identity" (Decode.null ())


login : LoginData -> Cmd Msg
login data =
    Http.post
        { url = "/api/login"
        , body = Http.jsonBody (encodeLoginData data)
        , expect = Http.expectJson (defaultErrorHandler LoginSuccess) decodeUserName
        }


defaultErrorHandler : (a -> Msg) -> Result Http.Error a -> Msg
defaultErrorHandler happyPath result =
    case result of
        Ok username ->
            happyPath username

        Err error ->
            HttpError error


logout : Cmd Msg
logout =
    Http.get
        { url = "/api/logout"
        , expect = Http.expectJson (defaultErrorHandler (\() -> LogoutSuccess)) decodeLogout
        }


type alias GameHeader =
    { id : Int
    , description : String
    , members : List GameMember
    }


decodeGameHeader : Decode.Decoder GameHeader
decodeGameHeader =
    Decode.map3 GameHeader
        (Decode.field "id" Decode.int)
        (Decode.field "description" Decode.string)
        (Decode.field "members" (Decode.list decodeGameMember))


type alias GameMember =
    { id : Int
    , username : String
    , role : MemberRole
    , accepted : Bool
    }


decodeGameMember : Decode.Decoder GameMember
decodeGameMember =
    Decode.map4 GameMember
        (Decode.field "id" Decode.int)
        (Decode.field "username" Decode.string)
        (Decode.field "role" decodeMemberRole)
        (Decode.field "accepted" Decode.bool)


encodeGameMember : GameMember -> Value
encodeGameMember gameMember =
    Encode.object
        [ ( "id", Encode.int <| gameMember.id )
        , ( "username", Encode.string <| gameMember.username )
        , ( "role", encodeMemberRole <| gameMember.role )
        , ( "accepted", Encode.bool <| gameMember.accepted )
        ]


decodeGameList : Decoder (List GameHeader)
decodeGameList =
    Decode.list decodeGameHeader


loadGameList : Cmd Msg
loadGameList =
    Http.get
        { url = "/api/game/list"
        , expect = Http.expectJson (defaultErrorHandler GameListSuccess) decodeGameList
        }


loadGame : GameId -> Cmd Msg
loadGame (GameId id) =
    Http.get
        { url = "/api/game/" ++ String.fromInt id
        , expect = Http.expectJson (defaultErrorHandler GameSuccess) (Decode.maybe decodeGameHeader)
        }


type alias GameCreate =
    { description : String }


encodeGameCreate : GameCreate -> Value
encodeGameCreate record =
    Encode.object
        [ ( "description", Encode.string <| record.description )
        ]


createGame : Model -> Cmd Msg
createGame model =
    Http.post
        { url = "/api/game/create"
        , body = Http.jsonBody (encodeGameCreate { description = model.newGameDescriptionField })
        , expect = Http.expectJson (defaultErrorHandler GameCreated) decodeGameHeader
        }


type alias UserInfo =
    { id : Int
    , username : String
    }


decodeUserInfo : Decoder UserInfo
decodeUserInfo =
    Decode.map2 UserInfo
        (Decode.field "id" Decode.int)
        (Decode.field "username" Decode.string)


loadFriendList : Cmd Msg
loadFriendList =
    Http.get
        { url = "/api/user/friends"
        , expect = Http.expectJson (defaultErrorHandler FriendListSuccess) (Decode.list decodeUserInfo)
        }


type SetupMessage
    = SetDescription String
      -- TODO: The GameMember type alias contains information that we do not need
      -- to send to the server. We should send a specialized type for this.
    | UpdateMember GameMember


encodeSetupMessage : SetupMessage -> Value
encodeSetupMessage message =
    case message of
        SetDescription description ->
            Encode.object [ ( "SetDescription", Encode.string <| description ) ]

        UpdateMember member ->
            Encode.object [ ( "UpdateMember", encodeGameMember <| member ) ]


postSetupMessage : GameId -> SetupMessage -> Cmd Msg
postSetupMessage (GameId gameId) message =
    Http.post
        { url = "/api/game/" ++ String.fromInt gameId ++ "/setup"
        , body = Http.jsonBody (encodeSetupMessage message)

        -- TODO: Here I will need a type like SetupMessage but for server
        -- responses. This will make more sense one I get a Websocket running.
        , expect = Http.expectJson (defaultErrorHandler (\() -> GameReload (GameId gameId))) (Decode.succeed ())
        }



-------------------------------------------------------------------------------
--------------------------- Taco helper functions -----------------------------
-------------------------------------------------------------------------------


loginTaco : String -> Taco -> Taco
loginTaco username taco =
    { taco | username = Just username }


logoutTaco : Taco -> Taco
logoutTaco taco =
    { taco | username = Nothing }

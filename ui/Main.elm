module Main exposing (main)

import Browser
import Browser.Navigation as Navigation
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
    , gameList : List GameHeader
    , route : Route
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
    | TypeNewGameDescription String
    | TryLogin
    | Logout
    | LoadGameList
    | GameListSuccess (List GameHeader)
    | OpenSingleGame GameId
    | OpenDashboard
    | ChangedUrl Url
    | CreateGame
    | GameCreated GameHeader


init : Value -> Url -> Navigation.Key -> ( Model, Cmd Msg )
init flags _ navKey =
    let
        identity =
            Decode.decodeValue decodeIdentity flags
                |> Result.withDefault Nothing

        taco =
            { username = identity, navKey = navKey }
    in
    ( { taco = taco
      , usernameField = ""
      , passwordField = ""
      , newGameDescriptionField = ""
      , gameList = []
      , route = Dashboard
      }
    , Cmd.none
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
            ( { model | taco = logoutTaco model.taco, gameList = [] }, Cmd.none )

        TypeUsername rawInput ->
            ( { model | usernameField = rawInput }, Cmd.none )

        TypePassword rawInput ->
            ( { model | passwordField = rawInput }, Cmd.none )

        TryLogin ->
            ( model, login { username = model.usernameField, password = model.passwordField } )

        Logout ->
            ( model, logout )

        LoadGameList ->
            ( model, loadGameList )

        GameListSuccess gameList ->
            ( { model | gameList = gameList }, Cmd.none )

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
            ( { model | gameList = newGame :: model.gameList }, Cmd.none )


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
        , gameOverviewTable model.gameList
        ]


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
            model.gameList
                |> List.filter (\game -> game.id == id)
                |> List.head

        gameElement =
            case maybeGame of
                Just game ->
                    gameDetailView model game

                Nothing ->
                    Element.text ("There is no game with id " ++ String.fromInt id)
    in
    Element.column []
        [ Element.text (String.fromInt id)
        , Input.button [] { label = Element.text "Return to Dashboard", onPress = Just OpenDashboard }
        , gameElement
        ]


gameDetailView : Model -> GameHeader -> Element Msg
gameDetailView _ game =
    Element.column [ spacing 15 ]
        [ Element.text game.description
        , memberTable game
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

        Invited ->
            Element.row [] [ icon [] Solid.envelope, Element.text "Invited" ]


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
    | Invited


fromStringMemberRole : String -> Decoder MemberRole
fromStringMemberRole string =
    case string of
        "BlackPlayer" ->
            Decode.succeed BlackPlayer

        "Invited" ->
            Decode.succeed Invited

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

        Invited ->
            "Invited"


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
    }


decodeGameMember : Decode.Decoder GameMember
decodeGameMember =
    Decode.map3 GameMember
        (Decode.field "id" Decode.int)
        (Decode.field "username" Decode.string)
        (Decode.field "role" decodeMemberRole)


decodeGameList : Decoder (List GameHeader)
decodeGameList =
    Decode.list decodeGameHeader


loadGameList : Cmd Msg
loadGameList =
    Http.get
        { url = "/api/game/list"
        , expect = Http.expectJson (defaultErrorHandler GameListSuccess) decodeGameList
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



-------------------------------------------------------------------------------
--------------------------- Taco helper functions -----------------------------
-------------------------------------------------------------------------------


loginTaco : String -> Taco -> Taco
loginTaco username taco =
    { taco | username = Just username }


logoutTaco : Taco -> Taco
logoutTaco taco =
    { taco | username = Nothing }

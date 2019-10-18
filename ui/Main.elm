module Main exposing (main)

import Browser
import Browser.Navigation as Navigation
import Element exposing (Element)
import Element.Events as Events
import Element.Input as Input
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
    | TryLogin
    | Logout
    | LoadGameList
    | GameListSuccess (List GameHeader)
    | OpenSingleGame GameId
    | OpenDashboard
    | ChangedUrl Url


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
      , gameList = []
      , route = Dashboard
      }
    , Cmd.none
    )


view : Model -> Browser.Document Msg
view model =
    { title = "Demo Game Client"
    , body = [ Element.layout [] <| document model ]
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
            ( { model | taco = logoutTaco model.taco }, Cmd.none )

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
    Element.column []
        [ loginInfo model
        , Input.button [] { label = Element.text "List Games", onPress = Just LoadGameList }
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
        [ Input.text []
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
            { header = Element.text "player"
            , width = Element.fill
            , view = \game -> Element.text game.owner
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
                    Element.text game.description

                Nothing ->
                    Element.text ("There is no game with id " ++ String.fromInt id)
    in
    Element.column []
        [ Element.text (String.fromInt id)
        , Input.button [] { label = Element.text "Return to Dashboard", onPress = Just OpenDashboard }
        , gameElement
        ]



-------------------------------------------------------------------------------
--------------------------- Http Api of the Server ----------------------------
-------------------------------------------------------------------------------


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
    , owner : String
    , description : String
    }


decodeGameHeader : Decode.Decoder GameHeader
decodeGameHeader =
    Decode.map3 GameHeader
        (Decode.field "id" Decode.int)
        (Decode.field "owner" Decode.string)
        (Decode.field "description" Decode.string)


encodeGameHeader : GameHeader -> Encode.Value
encodeGameHeader record =
    Encode.object
        [ ( "id", Encode.int <| record.id )
        , ( "owner", Encode.string <| record.owner )
        , ( "description", Encode.string <| record.description )
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



-------------------------------------------------------------------------------
--------------------------- Taco helper functions -----------------------------
-------------------------------------------------------------------------------


loginTaco : String -> Taco -> Taco
loginTaco username taco =
    { taco | username = Just username }


logoutTaco : Taco -> Taco
logoutTaco taco =
    { taco | username = Nothing }

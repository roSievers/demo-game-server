module Main exposing (main)

import Browser
import Browser.Navigation
import Element exposing (Element)
import Element.Input as Input
import Http
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode exposing (Value)
import Url exposing (Url)


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


type alias Model =
    { taco : Taco
    , usernameField : String
    , passwordField : String
    }


type alias Taco =
    { username : Maybe String
    }


emptyTaco =
    { username = Nothing }


type Msg
    = NoOp
    | LoginSuccess String
    | LogoutSuccess
    | HttpError Http.Error
    | TypeUsername String
    | TypePassword String
    | TryLogin
    | Logout


init : Value -> Url -> Browser.Navigation.Key -> ( Model, Cmd Msg )
init flags _ _ =
    let
        identity =
            Decode.decodeValue decodeIdentity flags
                |> Result.withDefault Nothing

        taco =
            { username = identity }
    in
    ( { taco = taco, usernameField = "", passwordField = "" }, Cmd.none )


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
onUrlChange _ =
    NoOp



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
            ( model, Cmd.none )

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



-------------------------------------------------------------------------------
--------------------- View function, written with elm-ui ----------------------
-------------------------------------------------------------------------------


document : Model -> Element Msg
document model =
    Element.column []
        [ loginInfo model
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
            Debug.log (Debug.toString error) (HttpError error)


logout : Cmd Msg
logout =
    Http.get
        { url = "/api/logout"
        , expect = Http.expectJson (defaultErrorHandler (\() -> LogoutSuccess)) decodeLogout
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

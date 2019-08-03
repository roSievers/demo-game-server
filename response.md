# Here we document possible responses of the server api

## Errors

Errors always have a .error member that specifies the type of the error.
Depending on the error, the response may carry additional fields.

    {"error":"ApiNotSpecified"}
    {"error":"ApiNotDefined","route":"some/route/that/does/not/exist"}
    {"error":"LoginFailed"}

## Identity token

We use identity token to manage logins. The /api/identity endpoint returns the current identity.

    {"identity":null}
    {"identity":"rolf"}
    {"error":"LoginFailed"}
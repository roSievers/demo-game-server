# Demo game server

[![dependency status](https://deps.rs/repo/github/rosievers/demo-game-server/status.svg)](https://deps.rs/repo/github/rosievers/demo-game-server)

Implements a multiplayer game website focusing on getting the infrastructure right without worrying
about the game. The game of choice for this project is [Nim](https://en.wikipedia.org/wiki/Nim)
with only a single heap.

The demo game server project implements routing in the (single page app) client.
This means most routes will return the frontend `index.html`. A directory of static resources
is published on the `/static` endpoint and the api is scoped to `/api`.

We publish a websocket connection on `/api/socket` that clients should connect to in order
to recieve push notifications about changes in games they are part of.

## Running the server

Make sure you have [Rust](https://www.rust-lang.org/) installed, this should come with Cargo.

You will need to prepare a sqlite database in `/home/nim.db` by running `/setup/install.sql`.
This creates a user "rolf" with password "judita" and a user "doro" with password "florian".

Next you must copy the `/setup/config.toml` file into your `home` folder and follow the instructions
inside.

Then navigate into the root folder of your checkout and execute

    cargo run

## Rebuilding the frontend

Make sure you have [Elm](https://elm-lang.org/) installed. Then run the following in the root folder.

    elm make --output=frontend/static/elm.js ui/Main.elm

During development, you can run this through `watch`, as the elm compiler is very fast.
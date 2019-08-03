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

You will need to prepare a sqlite database in `/home/nim.db` that stores the users.
Currently it only contains one table you need to create yourself:

    CREATE TABLE "users" (
        "id"	INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
        "username"	INTEGER NOT NULL UNIQUE,
        "password"	TEXT
    )

You shoud insert the following data to create a user "rolf" with password "judita" and a user
"doro" with password "florian".

    username password
    rolf     $rpbkdf2$0$AAAnEA==$Wih697v+F5NJGvnRIldzLw==$Bqx2PYzgR5Dg+wBELKRsmt/HaV9LZXQ4QcYK70HNbsU=$
    doro     $rpbkdf2$0$AAAnEA==$O/nqIkH/YIm/EzV8CfMIPA==$rN7hmPd3gmanCApEXQtsCd4SqA6+EKAu6HGqyvFJp50=$

Then navigate into the root folder of your checkout and execute

    cargo run
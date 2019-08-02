# demo-game-server
Implements a multiplayer game website focusing on getting the infrastructure right without worrying
about the game. The game of choice for this project is [Nim](https://en.wikipedia.org/wiki/Nim)
with only a single heap.

The demo game server project implements routing in the (single page app) client.
This means most routes will return the frontend `index.html`. A directory of static resources
is published on the `/static` endpoint and the api is scoped to `/api`.

We publish a websocket connection on `/api/socket` that clients should connect to in order
to recieve push notifications about changes in games they are part of.
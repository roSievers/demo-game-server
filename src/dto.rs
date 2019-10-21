/// This file defines data transfer objects.
use serde::{Deserialize, Serialize};

/// The information required to display a game in an overview table.
#[derive(Serialize, Deserialize)]
pub struct GameHeader {
    pub id: i64,
    pub description: String,
    pub members: Vec<Member>,
}

/// The information required to create a new game. The creator of the
/// game is determined on the server using login information and not
/// transfered in the DTO.
#[derive(Clone, Serialize, Deserialize)]
pub struct GameCreate {
    pub description: String,
}

/// A game can have several members with different roles.
/// TODO: Define which roles exist and wrap this in an enum.
#[derive(Serialize, Deserialize)]
pub struct Member {
    pub id: i64,
    pub username: String,
    pub role: i64,
}

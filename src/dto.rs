/// This file defines data transfer objects.
use serde::{Deserialize, Serialize};

/// The information required to display a game in an overview table.
#[derive(Serialize, Deserialize)]
pub struct GameHeader {
    pub id: i64,
    pub description: String,
    pub members: Vec<Member>,
}

#[derive(Serialize, Deserialize)]
pub struct Member {
    pub id: i64,
    pub username: String,
    pub role: i64,
}

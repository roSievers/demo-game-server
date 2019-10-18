/// This file defines data transfer objects.
use serde::{Deserialize, Serialize};

/// The information required to display a game in an overview table.
#[derive(Clone, Serialize, Deserialize)]
pub struct GameHeader {
    pub id: i64,
    pub owner: String,
    pub description: String,
}

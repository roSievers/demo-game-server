use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub struct GameHeader {
    pub owner: Option<i64>,
    pub description: String,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct WithID<T> {
    pub id: i64,
    pub data: T,
}

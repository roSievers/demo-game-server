/// This file defines data transfer objects.
use serde::{Deserialize, Serialize};
use std::convert::TryFrom;

/// The information required to display a game in an overview table.
#[derive(Serialize, Deserialize)]
pub struct GameHeader {
    pub id: i64,
    pub description: String,
    pub members: Vec<Member>,
}

/// The information required to create a new game. The creator of the game is
/// determined on the server using login information and not transfered in the
/// DTO.
#[derive(Clone, Serialize, Deserialize)]
pub struct GameCreate {
    pub description: String,
}

/// A game can have several members with different roles.
#[derive(Serialize, Deserialize)]
pub struct Member {
    pub id: i64,
    pub username: String,
    pub role: MemberRole,
}

/// The integers should be server only, the tags should be send to the client.
#[derive(Copy, Clone, Serialize, Deserialize)]
pub enum MemberRole {
    WhitePlayer = 1,
    BlackPlayer = 2,
    Watcher = 3,
    Invited = 4,
}

/// This implementation is important for database mapping.
impl rusqlite::types::FromSql for MemberRole {
    fn column_result(value: rusqlite::types::ValueRef) -> rusqlite::types::FromSqlResult<Self> {
        use rusqlite::types::FromSqlError::{InvalidType, OutOfRange};
        use rusqlite::types::ValueRef::Integer;
        use MemberRole::{BlackPlayer, Invited, Watcher, WhitePlayer};
        match value {
            Integer(1) => Ok(WhitePlayer),
            Integer(2) => Ok(BlackPlayer),
            Integer(3) => Ok(Watcher),
            Integer(4) => Ok(Invited),
            Integer(n) => Err(OutOfRange(n)),
            _ => Err(InvalidType),
        }
    }
}

impl rusqlite::types::ToSql for MemberRole {
    fn to_sql(&self) -> rusqlite::Result<rusqlite::types::ToSqlOutput> {
        use rusqlite::types::ToSqlOutput::Owned;
        use rusqlite::types::Value::Integer;
        Ok(Owned(Integer(*self as i64)))
        // Ok(Owned(Integer(match self {
        //     Self::WhitePlayer => 1,
        //     Self::BlackPlayer => 2,
        //     Self::Watcher => 3,
        //     Self::Invited => 4,
        // })))
    }
}

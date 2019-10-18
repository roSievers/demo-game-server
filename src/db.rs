use super::dto;
use super::types;
use actix_web::web;
use failure::Error;
use futures::Future;
use r2d2;
use r2d2_sqlite;
use rusqlite::params;

/// Database module
///
/// As a takeaway of the talk "Immutable Relational Data" by Richard Feldman
/// I decided to include no id values in any of the structs describing data.
/// Instead, the ids need to be managed separately.
///
/// https://www.youtube.com/watch?v=28OdemxhfbU

pub type Pool = r2d2::Pool<r2d2_sqlite::SqliteConnectionManager>;
pub type Connection = r2d2::PooledConnection<r2d2_sqlite::SqliteConnectionManager>;

pub fn check_password(
    username: String,
    password: String,
    pool: &Pool,
) -> impl Future<Item = bool, Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || check_password_(&username, &password, pool.get()?)).from_err()
}

fn check_password_(username: &str, password: &str, conn: Connection) -> Result<bool, Error> {
    use pbkdf2::pbkdf2_check;
    // TODO: Use a prepared statement
    let stmt = "SELECT password FROM user WHERE username = :username";

    let mut prep_stmt = conn.prepare(&stmt)?;
    let password_hash: String = prep_stmt
        .query_map_named(&[(":username", &username)], |row| row.get(0))?
        .nth(0)
        .unwrap()?;

    Ok(pbkdf2_check(password, &password_hash).is_ok())
}

pub fn create_game(
    game: types::GameHeader,
    pool: &Pool,
) -> impl Future<Item = i64, Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || create_game_(game, pool.get()?)).from_err()
}

fn create_game_(game: types::GameHeader, conn: Connection) -> Result<i64, Error> {
    conn.execute(
        "INSERT INTO game (owner, description) VALUES (?1, ?2)",
        params![game.owner, game.description],
    )?;
    let last_id = conn.last_insert_rowid();

    Ok(last_id)
}

pub fn get_game(
    id: i64,
    pool: &Pool,
) -> impl Future<Item = Option<types::GameHeader>, Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || get_game_(id, pool.get()?)).from_err()
}

fn get_game_(id: i64, conn: Connection) -> Result<Option<types::GameHeader>, Error> {
    let mut stmt = conn.prepare("SELECT owner, description FROM game WHERE id = ?1")?;
    let game_iter = stmt.query_map(params![id], |row| {
        Ok(types::GameHeader {
            owner: row.get(0)?,
            description: row.get(1)?,
        })
    })?;

    for game in game_iter {
        return Ok(Some(game?));
    }
    Ok(None)
}

pub fn all_games(
    pool: &Pool,
) -> impl Future<Item = Vec<dto::GameHeader>, Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || all_games_(pool.get()?)).from_err()
}

fn all_games_(conn: Connection) -> Result<Vec<dto::GameHeader>, Error> {
    let mut stmt = conn.prepare(
        "select game.id, user.username, game.description from game \
         inner join user on user.id = game.owner",
    )?;

    let game_iter = stmt.query_map(params![], |row| {
        Ok(dto::GameHeader {
            id: row.get(0)?,
            owner: row.get(1)?,
            description: row.get(2)?,
        })
    })?;

    let mut result = Vec::new();
    for game in game_iter {
        result.push(game?);
    }
    Ok(result)
}

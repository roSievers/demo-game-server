use super::dto;
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
    username: String,
    game: dto::GameCreate,
    pool: &Pool,
) -> impl Future<Item = dto::GameHeader, Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || create_game_(username, game, &pool.get()?)).from_err()
}

fn create_game_(
    username: String,
    game: dto::GameCreate,
    conn: &Connection,
) -> Result<dto::GameHeader, Error> {
    conn.execute(
        "INSERT INTO game (description) VALUES (?1)",
        params![game.description],
    )?;
    let game_id = conn.last_insert_rowid();

    let default_role = 1;

    conn.execute(
        "INSERT INTO game_member (user, game, role) VALUES \
         ((select id from user where username = ?1), ?2, ?3)",
        params![username, game_id, default_role],
    )?;

    Ok(dto::GameHeader {
        id: game_id,
        description: game.description,
        members: members_by_game_(game_id, conn)?,
    })
}

pub fn games_by_user(
    username: String,
    pool: &Pool,
) -> impl Future<Item = Vec<dto::GameHeader>, Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || games_by_user_(&username, &pool.get()?)).from_err()
}

/// This function takes a user id and returns all games that the user is a member of.
fn games_by_user_(username: &str, conn: &Connection) -> Result<Vec<dto::GameHeader>, Error> {
    let mut stmt = conn.prepare(
        "select game.id, game.description from game \
         inner join game_member on game_member.game = game.id \
         inner join user on user.id = game_member.user \
         where user.username = ?1",
    )?;

    let game_iter = stmt.query_map(params![username], |row| {
        let id = row.get(0)?;
        Ok(dto::GameHeader {
            id,
            description: row.get(1)?,
            members: members_by_game_(id, conn)?,
        })
    })?;

    let mut result = Vec::new();
    for game in game_iter {
        result.push(game?);
    }
    Ok(result)
}

/// This function takes a game id and returns all members of the game.
fn members_by_game_(game: i64, conn: &Connection) -> Result<Vec<dto::Member>, rusqlite::Error> {
    let mut stmt = conn.prepare(
        "select user.id, user.username, game_member.role from game_member \
         inner join user on user.id = game_member.user \
         where game_member.game = ?1",
    )?;
    let member_iter = stmt.query_map(params![game], |row| {
        Ok(dto::Member {
            id: row.get(0)?,
            username: row.get(1)?,
            role: row.get(2)?,
        })
    })?;
    let mut members = Vec::new();
    for member in member_iter {
        members.push(member?);
    }
    Ok(members)
}

pub fn game(
    game_id: i64,
    pool: &Pool,
) -> impl Future<Item = Option<dto::GameHeader>, Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || game_(game_id, &pool.get()?)).from_err()
}

fn game_(game_id: i64, conn: &Connection) -> Result<Option<dto::GameHeader>, Error> {
    let mut stmt = conn.prepare(
        "select game.description from game \
         where game.id = ?1",
    )?;

    let mut game_iter = stmt.query_map(params![game_id], |row| {
        Ok(dto::GameHeader {
            id: game_id,
            description: row.get(0)?,
            members: members_by_game_(game_id, conn)?,
        })
    })?;

    if let Some(row) = game_iter.next() {
        Ok(Some(row?))
    } else {
        Ok(None)
    }
}

pub fn all_users(pool: &Pool) -> impl Future<Item = Vec<dto::UserInfo>, Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || all_users_(&pool.get()?)).from_err()
}

fn all_users_(conn: &Connection) -> Result<Vec<dto::UserInfo>, Error> {
    let mut stmt = conn.prepare("select id, username from user")?;

    let user_iter = stmt.query_map(params![], |row| {
        Ok(dto::UserInfo {
            id: row.get(0)?,
            username: row.get(1)?,
        })
    })?;

    let mut users = Vec::new();
    for user in user_iter {
        users.push(user?);
    }
    Ok(users)
}

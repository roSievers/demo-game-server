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

    // The user automatically accepts their own game invite.
    conn.execute(
        "INSERT INTO game_member (user, game, role, accepted) VALUES \
         ((select id from user where username = ?1), ?2, ?3, 1)",
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
        "select user.id, user.username, game_member.role, game_member.accepted from game_member \
         inner join user on user.id = game_member.user \
         where game_member.game = ?1",
    )?;
    let member_iter = stmt.query_map(params![game], |row| {
        Ok(dto::Member {
            id: row.get(0)?,
            username: row.get(1)?,
            role: row.get(2)?,
            accepted: row.get(3)?,
        })
    })?;
    let mut members = Vec::new();
    for member in member_iter {
        members.push(member?);
    }
    Ok(members)
}

fn member_info_(
    game_id: i64,
    user_id: i64,
    conn: &Connection,
) -> Result<Option<dto::Member>, rusqlite::Error> {
    let mut stmt = conn.prepare(
        "select user.id, user.username, game_member.role, game_member.accepted from game_member \
         inner join user on user.id = game_member.user \
         where game_member.game = ?1
           and game_member.user = ?2",
    )?;
    let mut member_iter = stmt.query_map(params![game_id, user_id], |row| {
        Ok(dto::Member {
            id: row.get(0)?,
            username: row.get(1)?,
            role: row.get(2)?,
            accepted: row.get(3)?,
        })
    })?;

    if let Some(row) = member_iter.next() {
        Ok(Some(row?))
    } else {
        Ok(None)
    }
}

/// This function updates an existing member_info object. This matches via
/// the unique key (user_id, game_id) and does not change these values.
fn update_member_info_(
    game_id: i64,
    member_info: dto::Member,
    conn: &Connection,
) -> Result<(), rusqlite::Error> {
    conn.execute(
        "update game_member
        set role = ?1,
            accepted = ?2
        where user = ?3 and game = ?4",
        params![
            member_info.role,
            member_info.accepted,
            member_info.id,
            game_id
        ],
    )?;

    Ok(())
}

/// This function inserts a new member_info object. This requires that
/// the unique key (user_id, game_id) is not used yet.
fn insert_member_info_(
    game_id: i64,
    member_info: dto::Member,
    conn: &Connection,
) -> Result<(), rusqlite::Error> {
    conn.execute(
        "insert into game_member (user, game, role, accepted) values (?1, ?2, ?3, ?4)",
        params![
            member_info.id,
            game_id,
            member_info.role,
            member_info.accepted,
        ],
    )?;

    Ok(())
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

pub fn update_description(
    username: String,
    game_id: i64,
    new_description: String,
    pool: &Pool,
) -> impl Future<Item = (), Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || update_description_(username, game_id, new_description, &pool.get()?))
        .from_err()
}

fn update_description_(
    username: String,
    game_id: i64,
    new_description: String,
    conn: &Connection,
) -> Result<(), Error> {
    // TODO: The database module will contain business logic, until actix
    // updates to async await. Then we can move it outside.

    // Check if the user is a member of the game
    let user_id = get_user_id_(username, conn)?;
    let members = members_by_game_(game_id, conn)?;

    if members.iter().any(|member| Some(member.id) == user_id) {
        conn.execute(
            "update game set description = ?1 where id = ?2",
            params![new_description, game_id],
        )?;

        Ok(())
    } else {
        // TODO: Fail with error
        Ok(())
    }
}

fn get_user_id_(username: String, conn: &Connection) -> Result<Option<i64>, Error> {
    let mut stmt = conn.prepare("select id from user where username = ?1")?;

    let mut user_iter = stmt.query_map(params![username], |row| Ok(row.get(0)?))?;

    if let Some(row) = user_iter.next() {
        Ok(Some(row?))
    } else {
        Ok(None)
    }
}

pub fn update_member(
    username: String,
    game_id: i64,
    new_member: dto::Member,
    pool: &Pool,
) -> impl Future<Item = (), Error = actix_web::Error> {
    let pool = pool.clone();
    web::block(move || update_member_(username, game_id, new_member, &pool.get()?)).from_err()
}

fn update_member_(
    username: String,
    game_id: i64,
    mut new_member: dto::Member,
    conn: &Connection,
) -> Result<(), Error> {
    // TODO: The database module will contain business logic, until actix
    // updates to async await. Then we can move it outside.

    if let Some(user_id) = get_user_id_(username, conn)? {
        if member_info_(game_id, user_id, conn)?.is_none() {
            // The user giving the command is not part of the game.
            return Ok(());
        } else if let Some(mut member_info) = member_info_(game_id, new_member.id, conn)? {
            member_info.role = new_member.role;

            update_member_info_(game_id, member_info, conn)?;
        } else {
            // We make sure that the client can't decide to accept the request
            // for another user.
            new_member.accepted = false;

            insert_member_info_(game_id, new_member, conn)?;
        }

        Ok(())
    } else {
        // TODO: Fail with error
        Ok(())
    }
}

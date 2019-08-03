use actix_web::web;
use failure::Error;
use futures::Future;
use r2d2;
use r2d2_sqlite;

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
    let stmt = "SELECT password FROM users WHERE username = :username";

    let mut prep_stmt = conn.prepare(&stmt)?;
    let password_hash: String = prep_stmt
        .query_map_named(&[(":username", &username)], |row| row.get(0))?
        .nth(0)
        .unwrap()?;

    Ok(pbkdf2_check(password, &password_hash).is_ok())
}

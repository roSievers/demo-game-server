use actix_files::{Files, NamedFile};
use actix_web::{web, App, HttpRequest, HttpResponse, HttpServer};

use actix_identity::{CookieIdentityPolicy, Identity, IdentityService};
use std::collections::HashMap;
use std::sync::Mutex;

use futures::future::Future;

use serde::{Deserialize, Serialize};

use r2d2_sqlite;
use r2d2_sqlite::SqliteConnectionManager;

mod db;
use db::Pool;

/// Launches our demo server.
pub fn main() {
    // Read configuration file. This contains secrets and variable parameters.
    let config = Config::read_configuration().unwrap();
    let server_address = config.server_address();

    // Initialize shared server state (Not used right now, carried allong from the tutorial for reference.)
    let counter = web::Data::new(AppStateWithCounter {
        counter: Mutex::new(0),
    });

    // Start N db executor actors (N = number of cores avail)
    let manager = SqliteConnectionManager::file("./home/nim.db");
    let pool = Pool::new(manager).unwrap();

    HttpServer::new(move || {
        App::new()
            .data(pool.clone())
            .wrap(IdentityService::new(
                // <- create identity middleware
                CookieIdentityPolicy::new(config.security.identity_cookie_secret.as_bytes()) // <- create cookie identity policy
                    .name("auth-cookie")
                    .secure(false),
            ))
            // Register data that is shared between the server threads.
            // Currently this is only some dummy information to mention the concept in the code.
            .register_data(counter.clone()) // <- register the created data
            .route("/count", web::get().to(count_page))
            // We use the actix-files crate to serve static frontend content. Note that we use
            // .show_files_listing() for development which is generally not a good idea for production.
            .service(Files::new("/static", "./frontend/static").show_files_listing())
            .route("/api/identity", web::get().to(identity))
            .route("/api/login", web::post().to_async(login))
            .route("/api/logout", web::get().to(logout))
            // Serve the index page for all routes that do not match any earlier route.
            // We do not want this to happen to /api/.. routes, so we return a 404 on those first.
            .route("/api", web::get().to(api_error_page))
            .route("/api/{tail:.*}", web::get().to(api_error_page))
            .route("favicon.ico", web::get().to(favicon))
            .route("/{tail:.*}", web::get().to(index_page))
    })
    .bind(server_address)
    .unwrap()
    .run()
    .unwrap();
}

#[derive(Deserialize, Clone)]
struct Config {
    ip: String,
    port: u16,
    security: SecurityConfig,
}

#[derive(Deserialize, Clone)]
struct SecurityConfig {
    identity_cookie_secret: String,
    hashing_iteration_count: u32,
}

impl Config {
    fn server_address(&self) -> String {
        format!("{}:{}", self.ip, self.port)
    }

    fn read_configuration() -> std::io::Result<Self> {
        use std::fs::File;
        use std::io::prelude::*;

        let mut file = File::open("./home/config.toml")?;
        let mut contents = String::new();
        file.read_to_string(&mut contents)?;

        Ok(toml::from_str(&contents).unwrap())
    }
}

/// This is a placeholder for the "server state shared among threads" concept.
struct AppStateWithCounter {
    counter: Mutex<i32>, // <- Mutex is necessary to mutate safely across threads
}

/// This is a placeholder for the "server state shared among threads" concept.
fn count_page(data: web::Data<AppStateWithCounter>) -> String {
    let mut counter = data.counter.lock().unwrap(); // <- get counter's MutexGuard
    *counter += 1; // <- access counter inside MutexGuard

    format!("Request number: {}", counter) // <- response with count
}

/// Returns the index.html page. The file is reloaded from disk each time it is requested.
fn index_page() -> NamedFile {
    NamedFile::open("./frontend/index.html").unwrap()
}

/// Returns the favicon. The file is reloaded from disk each time it is requested.
fn favicon() -> NamedFile {
    NamedFile::open("./frontend/favicon.ico").unwrap()
}

/// All /api routes that are not implemented by the server return a 404 response and a JSON object
/// with a short description of the error.
fn api_error_page(req: HttpRequest) -> HttpResponse {
    if let Some(tail) = req.match_info().get("tail") {
        if !tail.is_empty() {
            HttpResponse::NotFound().json(
                ComplicatedErrorResult::new("ApiNotDefined".to_owned())
                    .info("route".to_owned(), tail.to_owned()),
            )
        } else {
            HttpResponse::NotFound().json(SimpleErrorResult::api_not_specified())
        }
    } else {
        HttpResponse::NotFound().json(SimpleErrorResult::api_not_specified())
    }
}

#[derive(Deserialize)]
struct LoginRequest {
    username: String,
    password: String,
}

#[derive(Serialize)]
struct LoginStatusInfo {
    identity: Option<String>,
}

#[derive(Serialize)]
struct SimpleErrorResult {
    error: String,
}

impl SimpleErrorResult {
    fn login_failed() -> Self {
        SimpleErrorResult {
            error: "LoginFailed".to_owned(),
        }
    }
    fn api_not_specified() -> Self {
        SimpleErrorResult {
            error: "ApiNotSpecified".to_owned(),
        }
    }
}

#[derive(Serialize)]
struct ComplicatedErrorResult {
    error: String,
    parameter: HashMap<String, String>,
}

impl ComplicatedErrorResult {
    fn new(error: String) -> Self {
        Self {
            error,
            parameter: HashMap::new(),
        }
    }
    fn info(mut self, key: String, value: String) -> Self {
        self.parameter.insert(key, value);
        self
    }
}

fn identity(id: Identity) -> HttpResponse {
    HttpResponse::Ok().json(LoginStatusInfo {
        identity: id.identity(),
    })
}

fn login(
    id: Identity,
    payload: web::Json<LoginRequest>,
    db: web::Data<Pool>,
) -> impl Future<Item = HttpResponse, Error = actix_web::Error> {
    let username = payload.username.clone();

    let result = db::check_password(payload.username.clone(), payload.password.clone(), &db);

    result
        .map_err(actix_web::Error::from)
        .map(move |is_password_correct| {
            if is_password_correct {
                id.remember(username.clone());

                HttpResponse::Ok().json(LoginStatusInfo {
                    identity: Some(username),
                })
            } else {
                id.forget();

                HttpResponse::Unauthorized().json(SimpleErrorResult::login_failed())
            }
        })
}

fn logout(id: Identity) -> HttpResponse {
    id.forget();
    identity(id)
}

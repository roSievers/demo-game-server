use actix_files::{Files, NamedFile};
use actix_web::{web, App, HttpRequest, HttpResponse, HttpServer};
use std::sync::Mutex;

/// Launches our demo server.
pub fn main() {
    // Initialize shared server state
    let counter = web::Data::new(AppStateWithCounter {
        counter: Mutex::new(0),
    });

    HttpServer::new(move || {
        App::new()
            // Register data that is shared between the server threads.
            // Currently this is only some dummy information to mention the concept in the code.
            .register_data(counter.clone()) // <- register the created data
            .route("/count", web::get().to(count_page))
            // We use the actix-files crate to serve static frontend content. Note that we use
            // .show_files_listing() for development which is generally not a good idea for production.
            .service(Files::new("/static", "./frontend/static").show_files_listing())
            // Serve the index page for all routes that do not match any earlier route.
            // We do not want this to happen to /api/.. routes, so we return a 404 on those first.
            .route("/api", web::get().to(api_error_page))
            .route("/api/{tail:.*}", web::get().to(api_error_page))
            .route("favicon.ico", web::get().to(favicon))
            .route("/{tail:.*}", web::get().to(index_page))
    })
    .bind("127.0.0.1:8088")
    .unwrap()
    .run()
    .unwrap();
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
    let error_message = if let Some(tail) = req.match_info().get("tail") {
        if !tail.is_empty() {
            format!("{{ error: \"ApiNotDefined\", content: \"{}\" }}", tail)
        } else {
            "{ error: \"ApiNotSpecified\" }".to_owned()
        }
    } else {
        "{ error: \"ApiNotSpecified\" }".to_owned()
    };

    HttpResponse::NotFound().body(error_message)
}
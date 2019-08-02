// Basic prototype javascript code

async function fetch_logout() {
    response = await fetch('/api/logout')
    json = await response.json()
    console.log(JSON.stringify(json))
}

async function fetch_identity() {
    response = await fetch('/api/identity')
    json = await response.json()
    console.log(JSON.stringify(json))
}

async function post_login(username, password) {
    postData('/api/login', { username: username, password: password })
        .then(data => console.log(JSON.stringify(data))) // JSON-string from `response.json()` call
        .catch(error => console.error(error));
}

function postData(url = '', data = {}) {
    // Default options are marked with *
    return fetch(url, {
        method: 'POST', // *GET, POST, PUT, DELETE, etc.
        cache: 'no-cache', // *default, no-cache, reload, force-cache, only-if-cached
        headers: {
            'Content-Type': 'application/json',
        },
        referrer: 'no-referrer', // no-referrer, *client
        body: JSON.stringify(data), // body data type must match "Content-Type" header
    })
        .then(response => response.json()); // parses JSON response into native JavaScript objects 
}
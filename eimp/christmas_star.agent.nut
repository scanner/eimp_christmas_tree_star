// Rocket Agent code from Electric Imp:
// https://github.com/electricimp/rocky
//
// The MIT License (MIT)
//
// Copyright (c) 2014 Electric Imp
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
//     all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//     THE SOFTWARE.
//*********************************************************
//******************** Library Classes ********************
//*********************************************************
class Rocky {
    _handlers = null;

    // Settings:
    _timeout = 10;
    _strictRouting = false;
    _allowUnsecure = false;
    _accessControl = true;

    constructor(settings = {}) {
        if ("timeout" in settings) _timeout = settings.timeout;
        if ("allowUnsecure" in settings) _allowUnsecure = settings.allowUnsecure;
        if ("strictRouting" in settings) _strictRouting = settings.strictRouting;
        if ("accessControl" in settings) _accessConrol = settings.accessControl;

        _handlers = {
            authorize = _defaultAuthorizeHandler.bindenv(this),
            onUnauthorized = _defaultUnauthorizedHandler.bindenv(this),
            onTimeout = _defaultTimeoutHandler.bindenv(this),
            onNotFound = _defaultNotFoundHandler.bindenv(this),
            onException = _defaultExceptionHandler.bindenv(this),
        };

        http.onrequest(_onrequest.bindenv(this));
    }

    /************************** [ PUBLIC FUNCTIONS ] **************************/
    function on(verb, signature, callback) {
        // Register this signature and verb against the callback
        verb = verb.toupper();
        signature = signature.tolower();
        if (!(signature in _handlers)) _handlers[signature] <- {};

        local routeHandler = Rocky.Route(callback);
        _handlers[signature][verb] <- routeHandler;

        return routeHandler;
    }

    function post(signature, callback) {
        return on("POST", signature, callback);
    }

    function get(signature, callback) {
        return on("GET", signature, callback);
    }

    function put(signature, callback) {
        return on("PUT", signature, callback);
    }

    function authorize(callback) {
        _handlers.authorize <- callback;
        return this;
    }

    function onUnauthorized(callback) {
        _handlers.onUnauthorized <- callback;
        return this;
    }

    function onTimeout(callback, timeout = 10) {
        _handlers.onTimeout <- callback;
        _timeout = timeout;
        return this;
    }

    function onNotFound(callback) {
        _handlers.onNotFound <- callback;
        return this;
    }

    function onException(callback) {
        _handlers.onException <- callback;
        return this;
    }

    // Adds access control headers
    function _addAccessControl(res) {
        res.header("Access-Control-Allow-Origin", "*")
        res.header("Access-Control-Allow-Headers", "Origin, X-Requested-With, Content-Type, Accept");
        res.header("Access-Control-Allow-Methods", "POST, PUT, GET, OPTIONS");
    }

    /************************** [ PRIVATE FUNCTIONS ] *************************/
    function _onrequest(req, res) {

        // Add access control headers if required
        if (_accessControl) _addAccessControl(res);

        // Setup the context for the callbacks
        local context = Rocky.Context(req, res);

        // Check for unsecure reqeusts
        if (_allowUnsecure == false && "x-forwarded-proto" in req.headers && req.headers["x-forwarded-proto"] != "https") {
            context.send(405, "HTTP not allowed.");
            return;
        }

        // Parse the request body back into the body
        try {
            req.body = _parse_body(req);
        } catch (e) {
            server.log("Parse error '" + e + "' when parsing:\r\n" + req.body)
            context.send(400, e);
            return;
        }

        // Look for a handler for this path
        local route = _handler_match(req);
        if (route) {
            // if we have a handler
            context.path = route.path;
            context.matches = route.matches;

            // parse auth
            context.auth = _parse_authorization(context);

            // Create timeout
            local onTimeout = _handlers.onTimeout;
            local timeout = _timeout;

            if (route.handler.hasTimeout()) {
                onTimeout = route.handler.onTimeout;
                timeout = route.handler.timeout;
            }

            context.setTimeout(_timeout, onTimeout);
            route.handler.execute(context, _handlers);
        } else {
            // if we don't have a handler
            _handlers.onNotFound(context);
        }
    }

    function _parse_body(req) {
        if ("content-type" in req.headers && req.headers["content-type"] == "application/json") {
            if (req.body == "" || req.body == null) return null;
            return http.jsondecode(req.body);
        }
        if ("content-type" in req.headers && req.headers["content-type"] == "application/x-www-form-urlencoded") {
            return http.urldecode(req.body);
        }
        if ("content-type" in req.headers && req.headers["content-type"].slice(0,20) == "multipart/form-data;") {
            local parts = [];
            local boundary = req.headers["content-type"].slice(30);
            local bindex = -1;
            do {
                bindex = req.body.find("--" + boundary + "\r\n", bindex+1);
                if (bindex != null) {
                    // Locate all the parts
                    local hstart = bindex + boundary.len() + 4;
                    local nstart = req.body.find("name=\"", hstart) + 6;
                    local nfinish = req.body.find("\"", nstart);
                    local fnstart = req.body.find("filename=\"", hstart) + 10;
                    local fnfinish = req.body.find("\"", fnstart);
                    local bstart = req.body.find("\r\n\r\n", hstart) + 4;
                    local fstart = req.body.find("\r\n--" + boundary, bstart);

                    // Pull out the parts as strings
                    local headers = req.body.slice(hstart, bstart);
                    local name = null;
                    local filename = null;
                    local type = null;
                    foreach (header in split(headers, ";\n")) {
                        local kv = split(header, ":=");
                        if (kv.len() == 2) {
                            switch (strip(kv[0]).tolower()) {
                                case "name":
                                    name = strip(kv[1]).slice(1, -1);
                                    break;
                                case "filename":
                                    filename = strip(kv[1]).slice(1, -1);
                                    break;
                                case "content-type":
                                    type = strip(kv[1]);
                                    break;
                            }
                        }
                    }
                    local data = req.body.slice(bstart, fstart);
                    local part = { "name": name, "filename": filename, "data": data, "content-type": type };

                    parts.push(part);
                }
            } while (bindex != null);

            return parts;
        }

        // Nothing matched, send back the original body
        return req.body;
    }

    function _parse_authorization(context) {
        if ("authorization" in context.req.headers) {
            local auth = split(context.req.headers.authorization, " ");

            if (auth.len() == 2 && auth[0] == "Basic") {
                // Note the username and password can't have colons in them
                local creds = http.base64decode(auth[1]).tostring();
                creds = split(creds, ":");
                if (creds.len() == 2) {
                    return { authType = "Basic", user = creds[0], pass = creds[1] };
                }
            } else if (auth.len() == 2 && auth[0] == "Bearer") {
                // The bearer is just the password
                if (auth[1].len() > 0) {
                    return { authType = "Bearer", user = auth[1], pass = auth[1] };
                }
            }
        }

        return { authType = "None", user = "", pass = "" };
    }

    function _extract_parts(routeHandler, path, regexp = null) {
        local parts = { path = [], matches = [], handler = routeHandler };

        // Split the path into parts
        foreach (part in split(path, "/")) {
            parts.path.push(part);
        }

        // Capture regular expression matches
        if (regexp != null) {
            local caps = regexp.capture(path);
            local matches = [];
            foreach (cap in caps) {
                parts.matches.push(path.slice(cap.begin, cap.end));
            }
        }

        return parts;
    }

    function _handler_match(req) {
        local signature = req.path.tolower();
        local verb = req.method.toupper();

        // ignore trailing /s if _strictRouting == false
        if(!_strictRouting) {
            while (signature.len() > 1 && signature[signature.len()-1] == '/') {
                signature = signature.slice(0, signature.len()-1);
            }
        }

        if ((signature in _handlers) && (verb in _handlers[signature])) {
            // We have an exact signature match
            return _extract_parts(_handlers[signature][verb], signature);
        } else if ((signature in _handlers) && ("*" in _handlers[signature])) {
            // We have a partial signature match
            return _extract_parts(_handlers[signature]["*"], signature);
        } else {
            // Let's iterate through all handlers and search for a regular expression match
            foreach (_signature,_handler in _handlers) {
                if (typeof _handler == "table") {
                    foreach (_verb,_callback in _handler) {
                        if (_verb == verb || _verb == "*") {
                            try {
                                local ex = regexp(_signature);
                                if (ex.match(signature)) {
                                    // We have a regexp handler match
                                    return _extract_parts(_callback, signature, ex);
                                }
                            } catch (e) {
                                // Don't care about invalid regexp.
                            }
                        }
                    }
                }
            }
        }
        return null;
    }

    /*************************** [ DEFAULT HANDLERS ] *************************/
    function _defaultAuthorizeHandler(context) {
        return true;
    }

    function _defaultUnauthorizedHandler(context) {
        context.send(401, "Unauthorized");
    }

    function _defaultNotFoundHandler(context) {
        context.send(404, format("No handler for %s %s", context.req.method, context.req.path));
    }

    function _defaultTimeoutHandler(context) {
        context.send(500, format("Agent Request Timedout after %i seconds.", _timeout));
    }

    function _defaultExceptionHandler(context, ex) {
        context.send(500, "Agent Error: " + ex);
    }
}

class Rocky.Route {
    handlers = null;
    timeout = null;

    _callback = null;

    constructor(callback) {
        handlers = {};
        timeout = 10;

        _callback = callback;
    }

    /************************** [ PUBLIC FUNCTIONS ] **************************/
    function execute(context, defaultHandlers) {
        try {
            // setup handlers
            foreach (handlerName, handler in defaultHandlers) {
                if (!(handlerName in handlers)) handlers[handlerName] <- handler;
            }

            if(handlers.authorize(context)) {
                _callback(context);
            }
            else {
                handlers.onUnauthorized(context);
            }
        } catch(ex) {
            handlers.onException(context, ex);
        }
    }

    function authorize(callback) {
        handlers.authorize <- callback;
        return this;
    }

    function onException(callback) {
        handlers.onException <- callback;
        return this;
    }

    function onUnauthorized(callback) {
        handlers.onUnauthorized <- callback;
        return this;
    }

    function onTimeout(callback, t = 10) {
        handlers.onTimeout <- callback;
        timeout = t;
        return this;
    }

    function hasTimeout() {
        return ("onTimeout" in handlers);
    }
}

class Rocky.Context {
    req = null;
    res = null;
    sent = false;
    id = null;
    time = null;
    auth = null;
    path = null;
    matches = null;
    timer = null;
    static _contexts = {};

    constructor(_req, _res) {
        req = _req;
        res = _res;
        sent = false;
        time = date();

        // Identify and store the context
        do {
            id = math.rand();
        } while (id in _contexts);
        _contexts[id] <- this;
    }

    /************************** [ PUBLIC FUNCTIONS ] **************************/
    function get(id) {
        if (id in _contexts) {
            return _contexts[id];
        } else {
            return null;
        }
    }

    function isbrowser() {
        return (("accept" in req.headers) && (req.headers.accept.find("text/html") != null));
    }

    function getHeader(key, def = null) {
        key = key.tolower();
        if (key in req.headers) return req.headers[key];
        else return def;
    }

    function setHeader(key, value) {
        return res.header(key, value);
    }

    function send(code, message = null) {
        // Cancel the timeout
        if (timer) {
            imp.cancelwakeup(timer);
            timer = null;
        }

        // Remove the context from the store
        if (id in _contexts) {
            delete Rocky.Context._contexts[id];
        }

        // Has this context been closed already?
        if (sent) {
            return false;
        }

        if (message == null && typeof code == "integer") {
            // Empty result code
            res.send(code, "");
        } else if (message == null && typeof code == "string") {
            // No result code, assume 200
            res.send(200, code);
        } else if (message == null && (typeof code == "table" || typeof code == "array")) {
            // No result code, assume 200 ... and encode a json object
            res.header("Content-Type", "application/json; charset=utf-8");
            res.send(200, http.jsonencode(code));
        } else if (typeof code == "integer" && (typeof message == "table" || typeof message == "array")) {
            // Encode a json object
            res.header("Content-Type", "application/json; charset=utf-8");
            res.send(code, http.jsonencode(message));
        } else {
            // Normal result
            res.send(code, message);
        }
        sent = true;
    }

    function setTimeout(timeout, callback) {
        // Set the timeout timer
        if (timer) imp.cancelwakeup(timer);
        timer = imp.wakeup(timeout, function() {
            if (callback == null) {
                send(502, "Timeout");
            } else {
                callback(this);
            }
        }.bindenv(this))
    }
}
/*********************************************************/
/*             -- End Rocky Library Classes --           */
/*********************************************************/

// -----------------------------------------------------------------------------
class Bullwinkle
{
    _handlers = null;
    _sessions = null;
    _partner  = null;
    _history  = null;
    _timeout  = 10;
    _retries  = 1;


    // .........................................................................
    constructor() {
        const BULLWINKLE = "bullwinkle";

        _handlers = { timeout = null, receive = null };
        _partner  = is_agent() ? device : agent;
        _sessions = { };
        _history  = { };

        // Incoming message handler
        _partner.on(BULLWINKLE, _receive.bindenv(this));
    }


    // .........................................................................
    function send(command, params = null) {

        // Generate an unique id
        local id = _generate_id();

        // Create and store the session
        _sessions[id] <- Bullwinkle_Session(this, id, _timeout, _retries);

        return _sessions[id].send("send", command, params);
    }


    // .........................................................................
    function ping() {

        // Generate an unique id
        local id = _generate_id();

        // Create and store the session
        _sessions[id] <- Bullwinkle_Session(this, id, _timeout, _retries);

        // Send it
        return _sessions[id].send("ping");
    }


    // .........................................................................
    function is_agent() {
        return (imp.environment() == ENVIRONMENT_AGENT);
    }

    // .........................................................................
    static function _getCmdKey(cmd) {
        return BULLWINKLE + "_" + cmd;
    }

    // .........................................................................
    function on(command, callback) {
        local cmdKey = Bullwinkle._getCmdKey(command);

        if (cmdKey in _handlers) {
            _handlers[cmdKey] = callback;
        } else {
            _handlers[cmdKey] <- callback
        }
    }
    // .........................................................................
    function onreceive(callback) {
        _handlers.receive <- callback;
    }


    // .........................................................................
    function ontimeout(callback, timeout = null) {
        _handlers.timeout <- callback;
        if (timeout != null) _timeout = timeout;
    }


    // .........................................................................
    function set_timeout(timeout) {
        _timeout = timeout;
    }


    // .........................................................................
    function set_retries(retries) {
        _retries = retries;
    }


    // .........................................................................
    function _generate_id() {
        // Generate an unique id
        local id = null;
        do {
            id = math.rand();
        } while (id in _sessions);
        return id;
    }

    // .........................................................................
    function _is_unique(context) {

        // Clean out old id's from the history
        local now = time();
        foreach (id,t in _history) {
            if (now - t > 100) {
                delete _history[id];
            }
        }

        // Check the current context for uniqueness
        local id = context.id;
        if (id in _history) {
            return false;
        } else {
            _history[id] <- time();
            return true;
        }
    }

    // .........................................................................
    function _clone_context(ocontext) {
        local context = {};
        foreach (k,v in ocontext) {
            switch (k) {
                case "type":
                case "id":
                case "time":
                case "command":
                case "params":
                    context[k] <- v;
            }
        }
        return context;
    }


    // .........................................................................
    function _end_session(id) {
        if (id in _sessions) {
            delete _sessions[id];
        }
    }


    // .........................................................................
    function _receive(context) {
        local id = context.id;
        switch (context.type) {
            case "send":
            case "ping":
                // build the command string
                local cmdKey = Bullwinkle._getCmdKey(context.command);

                // Immediately ack the message
                local response = { type = "ack", id = id, time = Bullwinkle_Session._timestamp() };
                if (!_handlers.receive && !_handlers[cmdKey]) {
                    response.type = "nack";
                }
                _partner.send(BULLWINKLE, response);

                // Then handed on to the callback
                if (context.type == "send" && (_handlers.receive || _handlers[cmdKey]) && _is_unique(context)) {
                    try {
                        // Prepare a reply function for shipping a reply back to the sender
                        context.reply <- function (reply) {
                            local response = { type = "reply", id = id, time = Bullwinkle_Session._timestamp() };
                            response.reply <- reply;
                            _partner.send(BULLWINKLE, response);
                        }.bindenv(this);

                        // Fire the callback
                        if (_handlers[cmdKey]) {
                            _handlers[cmdKey](context);
                        } else {
                            _handlers.receive(context);
                        }
                    } catch (e) {
                        // An unhandled exception should be sent back to the sender
                        local response = { type = "exception", id = id, time = Bullwinkle_Session._timestamp() };
                        response.exception <- e;
                        _partner.send(BULLWINKLE, response);
                    }
                }
                break;

            case "nack":
            case "ack":
                // Pass this packet to the session handler
                if (id in _sessions) {
                    _sessions[id]._ack(context);
                }
                break;

            case "reply":
                // This is a reply for an sent message
                if (id in _sessions) {
                    _sessions[id]._reply(context);
                }
                break;

            case "exception":
                // Pass this packet to the session handler
                if (id in _sessions) {
                    _sessions[id]._exception(context);
                }
                break;

            default:
                throw "Unknown context type: " + context.type;

        }
    }

}

// -----------------------------------------------------------------------------
class Bullwinkle_Session
{
    _handlers = null;
    _parent = null;
    _context = null;
    _timer = null;
    _timeout = null;
    _acked = false;
    _retries = null;

    // .........................................................................
    constructor(parent, id, timeout = 0, retries = 1) {
        _handlers = { ack = null, reply = null, timeout = null, exception = null };
        _parent = parent;
        _timeout = timeout;
        _retries = retries;
        _context = { time = _timestamp(), id = id };
    }

    // .........................................................................
    function onack(callback) {
        _handlers.ack = callback;
        return this;
    }

    // .........................................................................
    function onreply(callback) {
        _handlers.reply = callback;
        return this;
    }

    // .........................................................................
    function ontimeout(callback) {
        _handlers.timeout = callback;
        return this;
    }

    // .........................................................................
    function onexception(callback) {
        _handlers.exception = callback;
        return this;
    }

    // .........................................................................
    function send(type = "resend", command = null, params = null) {

        _retries--;

        if (type != "resend") {
            _context.type <- type;
            _context.command <- command;
            _context.params <- params;
        }

        if (_timeout > 0) _set_timer(_timeout);
        _parent._partner.send(BULLWINKLE, _context);

        return this;
    }

    // .........................................................................
    function _set_timer(timeout) {

        // Stop any current timers
        _stop_timer();

        // Start a fresh timer
        _timer = imp.wakeup(_timeout, _ontimeout.bindenv(this));
    }

    // .........................................................................
    function _ontimeout() {

        // Close down the timer and session
        _timer = null;

        if (!_acked && _retries > 0) {
            // Retry is required
            send();
        } else {
            // Close off this dead session
            _parent._end_session(_context.id)

            // If we are still waiting for an ack, throw a callback
            if (!_acked) {
                _context.latency <- _timestamp_diff(_context.time, _timestamp());
                if (_handlers.timeout) {
                    // Send the context to the session timeout handler
                    _handlers.timeout(_context);
                } else if (_parent._handlers.timeout) {
                    // Send the context to the global timeout handler
                    _parent._handlers.timeout(_context);
                }
            }
        }
    }

    // .........................................................................
    function _stop_timer() {
        if (_timer) imp.cancelwakeup(_timer);
        _timer = null;
    }

    // .........................................................................
    function _timestamp() {
        if (Bullwinkle.is_agent()) {
            local d = date();
            return format("%d.%06d", d.time, d.usec);
        } else {
            local d = math.abs(hardware.micros());
            return format("%d.%06d", d/1000000, d%1000000);
        }
    }


    // .........................................................................
    function _timestamp_diff(ts0, ts1) {
        // server.log(ts0 + " > " + ts1)
        local t0 = split(ts0, ".");
        local t1 = split(ts1, ".");
        local diff = (t1[0].tointeger() - t0[0].tointeger()) + (t1[1].tointeger() - t0[1].tointeger()) / 1000000.0;
        return math.fabs(diff);
    }


    // .........................................................................
    function _ack(context) {
        // Restart the timeout timer
        _set_timer(_timeout);

        // Calculate the round trip latency and mark the session as acked
        _context.latency <- _timestamp_diff(_context.time, _timestamp());
        _acked = true;

        // Fire a callback
        if (_handlers.ack) {
            _handlers.ack(_context);
        }

    }


    // .........................................................................
    function _reply(context) {
        // We can stop the timeout timer now
        _stop_timer();

        // Fire a callback
        if (_handlers.reply) {
            _context.reply <- context.reply;
            _handlers.reply(_context);
        }

        // Remove the history of this message
        _parent._end_session(_context.id)
    }


    // .........................................................................
    function _exception(context) {
        // We can stop the timeout timer now
        _stop_timer();

        // Fire a callback
        if (_handlers.exception) {
            _context.exception <- context.exception;
            _handlers.exception(_context);
        }

        // Remove the history of this message
        _parent._end_session(_context.id)
    }

}

/******************** Application Code ********************/
bullwinkle <- Bullwinkle();
bullwinkle.set_timeout(5);
bullwinkle.set_retries(3);

app <- Rocky();

app.get("/", function(context) {
    context.send("Hello World");
});

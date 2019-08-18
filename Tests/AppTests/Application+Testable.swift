import Vapor
@testable import App
import Authentication
import FluentPostgreSQL

extension Application {
    
    // This function allows you to create a testable Application object.
    // You can specify environment arguments, if required.
    static func testable(envArgs: [String]? = nil) throws
        -> Application {
            var config = Config.default()
            var services = Services.default()
            var env = Environment.testing
            if let environmentArgs = envArgs {
                env.arguments = environmentArgs
            }
            try App.configure(&config, &env, &services)
            let app = try Application(
                config: config,
                environment: env,
                services: services)
            try App.boot(app)
            return app
    }
    
    // This uses the function above to create an application that runs the revert command and then runs the
    // migrate command. This simplifies resetting the database in each test.
    static func reset() throws {
        let revertEnvironment = ["vapor", "revert", "--all", "-y"]
        try Application.testable(envArgs: revertEnvironment)
            .asyncRun()
            .wait()
        let migrateEnvironment = ["vapor", "migrate", "-y"]
        try Application.testable(envArgs: migrateEnvironment)
            .asyncRun()
            .wait()
    }
    
    
    // Define a method that sends a request to a path and returns a Response.
    // Allow the HTTP method and headers to be set; this is for later tests.
    // Also allow an optional, generic Content to be provided for the body.
    func sendRequest<T>(to path: String, method: HTTPMethod, headers: HTTPHeaders = .init(), body: T? = nil, loggedInRequest: Bool = false, loggedInUser: User? = nil) throws -> Response where T: Content {
        var headers = headers
        if loggedInRequest || loggedInUser != nil {
            let username = loggedInUser?.username ?? "admin"
            let credentials = BasicAuthorization(username: username, password: "password")
            
            var tokenHeaders = HTTPHeaders()
            tokenHeaders.basicAuthorization = credentials
            
            let tokenResponse = try self.sendRequest(to: "/api/users/login", method: .POST, headers: tokenHeaders)
            
            let token = try tokenResponse.content.syncDecode(Token.self)
            
            headers.add(name: .authorization, value: "Bearer \(token.token)")
        }
        let responder = try self.make(Responder.self)
        let request = HTTPRequest(method: method, url: URL(string: path)!, headers: headers)
        let wrappedRequest = Request(http: request, using: self)
        if let body = body {
            try wrappedRequest.content.encode(body)
        }
        return try responder.respond(to: wrappedRequest).wait()
    }
    
    // Define a convenience method that sends a request to a path without a body.
    func sendRequest(to path: String, method: HTTPMethod, headers: HTTPHeaders = .init(), loggedInRequest: Bool = false, loggedInUser: User? = nil) throws -> Response {
        let emptyContent: EmptyContent? = nil
        return try sendRequest(to: path, method: method, headers: headers, body: emptyContent, loggedInRequest: loggedInRequest, loggedInUser: loggedInUser)
    }
    
    // Define a method that sends a request to a path and accepts a generic Content type.
    // This convenience method allows you to send a request when you don’t care about the response.
    func sendRequest<T>(to path: String, method: HTTPMethod, headers: HTTPHeaders, data: T, loggedInRequest: Bool = false, loggedInUser: User? = nil) throws where T: Content {
        _ = try self.sendRequest(to: path, method: method, headers: headers, body: data, loggedInRequest: loggedInRequest, loggedInUser: loggedInUser)
    }
    
    // Define a generic method that accepts a Content type and Decodable type to get a response to a request.
    func getResponse<C, T>(to path: String, method: HTTPMethod = .GET, headers: HTTPHeaders = .init(), data: C? = nil, decodeTo type: T.Type, loggedInRequest: Bool = false, loggedInUser: User? = nil) throws -> T where C: Content, T: Decodable {
        let response = try self.sendRequest(to: path, method: method, headers: headers, body: data, loggedInRequest: loggedInRequest, loggedInUser: loggedInUser)
        return try response.content.decode(type).wait()
    }
    
    // Define a generic convenience method that accepts a Decodable type to get a response to a
    // request without providing a body.
    func getResponse<T>(to path: String, method: HTTPMethod = .GET, headers: HTTPHeaders = .init(), decodeTo type: T.Type, loggedInRequest: Bool = false, loggedInUser: User? = nil) throws -> T where T: Decodable {
        let emptyContent: EmptyContent? = nil
        return try self.getResponse(to: path, method: method, headers: headers, data: emptyContent, decodeTo: type, loggedInRequest: loggedInRequest, loggedInUser: loggedInUser)
    }
}

// This defines an empty Content type to use when there’s no body to send in a request.
// Since you can’t define nil for a generic type, EmptyContent allows you to provide an type to satisfy the compiler.
struct EmptyContent: Content {}

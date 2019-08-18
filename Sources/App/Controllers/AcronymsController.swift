import Vapor
import Fluent
import Authentication

struct AcronymsController: RouteCollection {
    
    // Boot is used to register all routes and is required by RouteCollection
    func boot(router: Router) throws {
        // Since all the api use the same 2 first paths and we dont want to have to change that path in multiple
        // locations if anything changes, use a route group instead
        let acronymsRoutes = router.grouped("api", "acronyms")
        acronymsRoutes.get(use: getAllHandler)
        acronymsRoutes.get(Acronym.parameter, use: getHandler)
        acronymsRoutes.get("search", use: searchHandler)
        acronymsRoutes.get("first", use: getFirstHandler)
        acronymsRoutes.get("sorted", use: sortedHandler)
        acronymsRoutes.get(Acronym.parameter, "user", use: getUserHandler)
        acronymsRoutes.get(Acronym.parameter, "categories", use: getCategoriesHandler)
        // get most recently updated acronyms
        acronymsRoutes.get("mostRecent", use: getMostRecentAcronyms)
        // p. 450 Get acronyms with user models
        acronymsRoutes.get("users", use: getAcronymsWithUser)
        // p.452 Using raw SQL queries
        acronymsRoutes.get("raw", use: getAllAcronymsRaw)
        // **** This ensures only requests authenticated using HTTP basic authentication can create acronyms. ***
        
        // Create a TokenAuthenticationMiddleware for User.
        // This uses BearerAuthenticationMiddleware to extract the bearer token out of the request.
        // The middleware then converts this token into a logged in user.
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        let guardAuthMiddleware = User.guardAuthMiddleware()
        // Create a route group using tokenAuthMiddleware and guardAuthMiddleware to protect the route for creating an acronym with token authentication.
        // This ensures that only authenticated users can create, edit and delete acronyms, and add categories to acronyms. Unauthenticated users can still view details about acronyms.
        let tokenAuthGroup = acronymsRoutes.grouped(tokenAuthMiddleware, guardAuthMiddleware)
        tokenAuthGroup.post(AcronymCreateData.self, use: createHandler)
        tokenAuthGroup.delete(Acronym.parameter, use: deleteHandler)
        tokenAuthGroup.put(Acronym.parameter, use: updateHandler)
        tokenAuthGroup.post(Acronym.parameter, "categories", Category.parameter, use: addCategoriesHandler)
        tokenAuthGroup.delete(Acronym.parameter, "categories", Category.parameter, use: removeCategoriesHandler)
    }
    
    // MARK: - CRUD Operations
    
    // POST a new acronym
    func createHandler(_ req: Request, data: AcronymCreateData) throws -> Future<Acronym> {
        let user = try req.requireAuthenticated(User.self)
        let acronym = try Acronym(short: data.short, long: data.long, userID: user.requireID())
        return acronym.save(on: req)
    }
    
    // GET all Acronyms
    func getAllHandler(_ req: Request) throws -> Future<[Acronym]> {
        return Acronym.query(on: req).all()
    }
    
    // GET a single acronym
    func getHandler(_ req: Request) throws -> Future<Acronym> {
        return try req.parameters.next(Acronym.self)
    }
    
    
    // PUT Update Acronym
    func updateHandler(_ req: Request) throws -> Future<Acronym> {
        return try flatMap(to: Acronym.self, req.parameters.next(Acronym.self), req.content.decode(AcronymCreateData.self)) { acronym, updatedData in
            acronym.short = updatedData.short
            acronym.long = updatedData.long
            let user = try req.requireAuthenticated(User.self)
            acronym.userID = try user.requireID()
            return acronym.save(on: req)
        }
    }
    
    // DELETE Remove Acronym
    func deleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
            return try req.parameters.next(Acronym.self).delete(on: req).transform(to: .noContent)
    }
    
    // Search for Acronyms with search term
    func searchHandler(_ req: Request) throws -> Future<[Acronym]> {
        guard let searchTerm = req.query[String.self, at: "term"] else {
            throw Abort(.badRequest)
        }
        return Acronym.query(on: req).group(.or) { or in
            or.filter(\.short == searchTerm)
            or.filter(\.long == searchTerm)
            }.all()
    }
    
    // GET First acronym in list
    func getFirstHandler(_ req: Request) throws -> Future<Acronym> {
        return Acronym.query(on: req)
            .first()
            .unwrap(or: Abort(.notFound))
    }
    
    // Sort Acronyms
    func sortedHandler(_ req: Request) throws -> Future<[Acronym]> {
        return Acronym.query(on: req).sort(\.short, .ascending).all()
    }
    
    // Get the parents of the Acronym
    func getUserHandler(_ req: Request) throws -> Future<User.Public> {
        return try req
            .parameters.next(Acronym.self)
            .flatMap(to: User.Public.self) { acronym in
                acronym.user.get(on: req).convertToPublic()
        }
    }
    
    // add sibling relationship between Acronym and Category
    func addCategoriesHandler(_ req: Request) throws -> Future<HTTPStatus> {
        return try flatMap(to: HTTPStatus.self, req.parameters.next(Acronym.self), req.parameters.next(Category.self)) { acronym, category in
            return acronym.categories.attach(category, on: req).transform(to: .created)
        }
    }
    
    // get categories using the sibling relationship and pivot
    func getCategoriesHandler(_ req: Request) throws -> Future<[Category]> {
        return try req.parameters.next(Acronym.self).flatMap(to: [Category].self) { acronym in
            try acronym.categories.query(on: req).all()
        }
    }
    
    // remove the relationship between acronym and category
    func removeCategoriesHandler(_ req: Request) throws -> Future<HTTPStatus> {
        return try flatMap(to: HTTPStatus.self, req.parameters.next(Acronym.self), req.parameters.next(Category.self)) { acronym, category in
            return acronym.categories.detach(category, on: req).transform(to: .noContent)
        }
    }
    
    // p.439 Timestamping
    func getMostRecentAcronyms(_ req: Request) throws -> Future<[Acronym]> {
        // sort by most recently updated at first
        return Acronym.query(on: req).sort(\.updatedAt, .descending).all()
    }
    
    // p.450 Joins - joining models in one request
    func getAcronymsWithUser(_ req: Request) throws -> Future<[AcronymWithUser]> {
        return Acronym.query(on: req).join(\User.id, to: \Acronym.userID).alsoDecode(User.self).all().map(to: [AcronymWithUser].self) { acronymUserPairs in
            acronymUserPairs.map { acronym, user -> AcronymWithUser in
                AcronymWithUser(id: acronym.id, short: acronym.short, long: acronym.long, user: user.convertToPublic())
            }
        }
    }
    
    // p.451 Raw SQL queries to solve N+1 problem more efficiently
    func getAllAcronymsRaw(_ req: Request) throws -> Future<[Acronym]> {
        return req.withPooledConnection(to: .psql) { conn in
            conn.raw("SELECT * from \"Acronym\"").all(decoding: Acronym.self)
        }
    }
    
}

struct AcronymCreateData: Content {
    let short: String
    let long: String
}

struct AcronymWithUser: Content {
    let id: Int?
    let short: String
    let long: String
    let user: User.Public
}

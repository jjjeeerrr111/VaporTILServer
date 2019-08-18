import Vapor
import Crypto
import Fluent

struct UsersController: RouteCollection {
    func boot(router: Router) throws {
        let userRoute = router.grouped("api", "users")
        userRoute.get(use: getAllHandler)
        userRoute.get(User.parameter, use: getHandler)
        userRoute.get(User.parameter, "acronyms", use: getAcronymsHandler)
        // p. 448 Nested models
        userRoute.get("acronyms", use: getAllUsersWithAcronyms)
        
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let basicAuthGroup = userRoute.grouped(basicAuthMiddleware)
        basicAuthGroup.post("login", use: loginHandler)
        
        
        // Using tokenAuthMiddleware and guardAuthMiddleware ensures only authenticated users can create other users.
        // This prevents anyone from creating a user to send requests to the routes you’ve just protected!
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthGroup = userRoute.grouped(tokenAuthMiddleware, guardAuthMiddleware)
        tokenAuthGroup.post(User.self, use: createHandler)
        // soft delete a user
        tokenAuthGroup.delete(User.parameter, use: deleteHandler)
        // restore a soft deleted user
        tokenAuthGroup.post(UUID.parameter, "restore", use: restoreHandler)
        // force delete a user
        tokenAuthGroup.delete(User.parameter, "force", use: forceDeleteHandler)
        // Versioning the api p.387
        let usersV2Route = router.grouped("api", "v2", "users")
        usersV2Route.get(User.parameter, use: getV2Handler)
    }
    
    func createHandler(_ req: Request, user: User) throws -> Future<User.Public> {
        user.password = try BCrypt.hash(user.password)
        return user.save(on: req).convertToPublic()
    }
    
    func getAllHandler(_ req: Request) throws -> Future<[User.Public]> {
        return User.query(on: req).decode(data: User.Public.self).all()
    }

    func getHandler(_ req: Request) throws -> Future<User.Public> {
        return try req.parameters.next(User.self).convertToPublic()
    }
    
    // p.387
    func getV2Handler(_ req: Request) throws -> Future<User.PublicV2> {
        return try req.parameters.next(User.self).convertToPublicV2()
    }
    
    func getAcronymsHandler(_ req: Request) throws -> Future<[Acronym]> {
        return try req
            // first get the user from the parameters passed into the route
            .parameters.next(User.self)
            // convert the user to array of acronyms and query all acronyms for that user
            .flatMap(to: [Acronym].self) { user in
            try user.acronyms.query(on: req).all()
        }
    }
    
    func loginHandler(_ req: Request) throws -> Future<Token> {
        let user = try req.requireAuthenticated(User.self)
        let token = try Token.generate(for: user)
        return token.save(on: req)
    }
    
    // p.432 Soft deleting a user
    func deleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        
        let requestUser = try req.requireAuthenticated(User.self)
        
        guard requestUser.userType == .admin else {
            throw Abort(.forbidden)
        }
        
        return try req.parameters.next(User.self).delete(on: req).transform(to: .noContent)
    }
    
    // p.433 Restoring a soft deleted user
    func restoreHandler(_ req: Request) throws -> Future<HTTPStatus> {
        
        let requestUser = try req.requireAuthenticated(User.self)
        
        guard requestUser.userType == .admin else {
            throw Abort(.forbidden)
        }
        
        let userID = try req.parameters.next(UUID.self)
        
        return User.query(on: req, withSoftDeleted: true).filter(\.id == userID).first().flatMap(to: HTTPStatus.self) { user in
            guard let user = user else {
                throw Abort(.notFound)
            }
            
            return user.restore(on: req).transform(to: .ok)
        }
    }
    
    // p.436 force deleting a user
    func forceDeleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        
        let requestUser = try req.requireAuthenticated(User.self)
        
        guard requestUser.userType == .admin else {
            throw Abort(.forbidden)
        }
        
        return try req.parameters.next(User.self).flatMap(to: HTTPStatus.self) { user in
            user.delete(force: true, on: req).transform(to: .noContent)
        }
    }
    
    // p.448 Nested models request
    func getAllUsersWithAcronyms(_ req: Request) throws -> Future<[UserWithAcronyms]> {
        return User.query(on: req).all().flatMap(to: [UserWithAcronyms].self) { users in
            try users.map { user in
                try user.acronyms.query(on: req).all().map { acronyms in
                    UserWithAcronyms(id: user.id, name: user.name, username: user.username, acronyms: acronyms)
                }
            }.flatten(on: req)
        }
    }
}

// p.447 Nested models

struct UserWithAcronyms: Content {
    let id: UUID?
    let name: String
    let username: String
    let acronyms: [Acronym]
}

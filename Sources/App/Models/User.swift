import Foundation
import Vapor
import FluentPostgreSQL
import Authentication

final class User: Codable {
    var id: UUID?
    var name: String
    var username: String
    var password: String
    var email: String
    var profilePicture: String?
    var twitterURL: String?
    var deletedAt: Date?
    var userType: UserType
    
    init(name: String, username: String, password: String, email: String, profilePicture: String? = nil, twitterURL: String? = nil, userType: UserType = .standard) {
        self.username = username
        self.name = name
        self.password = password
        self.email = email
        self.profilePicture = profilePicture
        self.twitterURL = twitterURL
        self.userType = userType
    }
    
    final class Public: Codable {
        var id: UUID?
        var name: String
        var username: String
        
        init(id: UUID?, name: String, username: String) {
            self.id = id
            self.name = name
            self.username = username
        }
    }
    
    final class PublicV2: Codable {
        var id: UUID?
        var name: String
        var username: String
        var twitterURL: String?
        
        init(id: UUID?, name: String, username: String, twitterURL: String? = nil) {
            self.id = id
            self.name = name
            self.username = username
            self.twitterURL = twitterURL
        }
    }
}

extension User: PostgreSQLUUIDModel {
    // p.430
    static let deletedAtKey: TimestampKey? = \.deletedAt
    
    // p.445 lifecycle hooks
    func willCreate(on conn: PostgreSQLConnection) throws -> Future<User> {
        return User.query(on: conn).filter(\.username == self.username).count().map(to: User.self) { count in
            guard count == 0 else {
                throw BasicValidationError("Username already exists")
            }
            return self
        }
    }
}
extension User: Content {}
extension User: Parameter {}
// This conforms User.Public to Content, allowing you to return the public view in responses.
extension User.Public: Content {}
// This adds a new public content since we added the twitterURL in a migration p.386
extension User.PublicV2: Content {}
extension User {
    func convertToPublic() -> User.Public {
        return User.Public(id: id, name: name, username: username)
    }
    
    func convertToPublicV2() -> User.PublicV2 {
        return User.PublicV2(id: id, name: name, username: username, twitterURL: twitterURL)
    }
}
extension Future where T: User {
    func convertToPublic() -> Future<User.Public> {
        return self.map(to: User.Public.self) { user in
            return user.convertToPublic()
        }
    }
    
    func convertToPublicV2() -> Future<User.PublicV2> {
        return self.map(to: User.PublicV2.self) { user in
            return user.convertToPublicV2()
        }
    }
}
extension User: Migration {
    
    // This implement a custom migration ensuring that the username is unique.
    // Any attempts to create a duplicate username will result in an error.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) { builder in
            try addProperties(to: builder)
            builder.unique(on: \.username)
            builder.unique(on: \.email)
        }
    }
}

// This is used to get a models' children, in this case Acronyms created by the user
extension User {
    
    var acronyms: Children<User, Acronym> {
        return children(\.userID)
    }
}

// This allows you to use the HTTP Basic helpers in the authentication module.
extension User: BasicAuthenticatable {
    static let usernameKey: UsernameKey = \User.username
    static let passwordKey: PasswordKey = \User.password
}

extension User: TokenAuthenticatable {
    typealias TokenType = Token
}

// Database seeding - create a user when Vapor first boots up
struct AdminUser: Migration {
    typealias Database = PostgreSQLDatabase
    
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        let password = try? BCrypt.hash("password")
        guard let hashedPassword = password else {
            fatalError("Failed to create admin user")
        }
        
        let user = User(name: "Admin", username: "admin", password: hashedPassword, email: "admin@localhost.com", userType: .admin)
        
        return user.save(on: connection).transform(to: ())
    }
    
    static func revert(on connection: PostgreSQLConnection) -> Future<Void> {
        return .done(on: connection)
    }
}

// Caching web sessions
// Conform User to PasswordAuthenticatable.
// This allows Vapor to authenticate users with a username and password when they log in.
// Since you’ve already implemented the necessary properties for PasswordAuthenticatable in BasicAuthenticatable, there’s nothing to do here.
extension User: PasswordAuthenticatable {}
// Conform User to SessionAuthenticatable.
// This allows the application to save and retrieve your user as part of a session.
extension User: SessionAuthenticatable {}

@testable import App
import FluentPostgreSQL
import Crypto

extension User {
    
    // This function saves a user, created with the supplied details, in the database.
    // It has default values so you don’t have to provide any if you don’t care about them.
    static func create(name: String = "Luke", username: String? = nil, on connection: PostgreSQLConnection) throws -> User {
        let createUsername: String
        // 2
        if let suppliedUsername = username {
            createUsername = suppliedUsername
            // 3
        } else {
            createUsername = UUID().uuidString
        }
        // 4
        let password = try BCrypt.hash("password")
        let user = User(name: name, username: createUsername, password: password, email: "\(createUsername)@test.com")
        return try user.save(on: connection).wait()
    }
}

extension Acronym {
    static func create(short: String = "TIL", long: String = "Today I Learned", user: User? = nil, on connection: PostgreSQLConnection) throws -> Acronym {
        var acronymsUser = user
        if acronymsUser == nil {
            acronymsUser = try User.create(on: connection)
        }
        let acronym = Acronym(short: short, long: long, userID: acronymsUser!.id!)
        return try acronym.save(on: connection).wait()
    }
}

extension App.Category {
    static func create(name: String = "Random", on connection: PostgreSQLConnection) throws -> App.Category {
        let category = Category(name: name)
        return try category.save(on: connection).wait()
    }
}

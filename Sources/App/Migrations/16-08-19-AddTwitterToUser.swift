import FluentPostgreSQL
import Vapor

struct AddTwitterURLToUser: Migration {
    typealias Database = PostgreSQLDatabase
    
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.update(User.self, on: connection) { builder in
            builder.field(for: \.twitterURL)
        }
    }
    
    static func revert(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.update(User.self, on: connection) { builder in
            builder.deleteField(for: \.twitterURL)
        }
    }
}

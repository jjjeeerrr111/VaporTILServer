import Vapor
import FluentPostgreSQL

final class Acronym: Codable {
    var id: Int?
    var short: String
    var long: String
    var userID: User.ID // this sets up the parent relationship in the db
    // p.438 Timestamps
    var createdAt: Date?
    var updatedAt: Date?
    
    init(short: String, long: String, userID: User.ID) {
        self.short = short
        self.long = long
        self.userID = userID
    }
}

// Conform to Fluent Model
extension Acronym: PostgreSQLModel {
    
    // automatic timestamping by fluent p. 438
    // Fluent looks for these keys when creating and updating models.
    // If they exist, Fluent sets the date for the corresponding action. That’s all that’s required
    static let createdAtKey: TimestampKey? = \.createdAt
    static let updatedAtKey: TimestampKey? = \.updatedAt
}
// Make the model conform to migration for database scheme
extension Acronym: Migration {
    
    // Add foreign key constraint set up to ensure:
    // • You can’t create acronyms with users that don’t exist.
    // • You can’t delete users until you’ve deleted all their acronyms.
    // • You can’t delete the user table until you’ve deleted the acronym table.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) { builder in
            try addProperties(to: builder)
            // Add a reference between the userID property on Acronym and the id property on
            // User. This sets up the foreign key constraint between the two tables.
            builder.reference(from: \.userID, to: \User.id)
        }
    }
}
// Conform to Content to be able to use Codable
extension Acronym: Content {}
extension Acronym: Parameter {}

extension Acronym {
    
    // This is the computed property that makes it possible to get the parent of the object (a User)
    var user: Parent<Acronym, User> {
        return parent(\.userID)
    }
    
    // This is the computed property for adding a pivot (sibling relationship) between category and acronym models
    var categories: Siblings<Acronym, Category, AcronymCategoryPivot> {
        return siblings()
    }
}



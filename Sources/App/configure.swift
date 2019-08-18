import FluentPostgreSQL
import Vapor
import Leaf
import Authentication
import SendGrid
/// Called before your application initializes.
public func configure(_ config: inout Config, _ env: inout Environment, _ services: inout Services) throws { // 2
    try services.register(FluentPostgreSQLProvider())
    try services.register(LeafProvider())
    // This registers the necessary services with your application to ensure authentication works.
    try services.register(AuthenticationProvider())
    // This registers SendGrid to send reset password emails
    try services.register(SendGridProvider())
    guard let sendGridAPIKey = Environment.get("SENDGRID_API_KEY") else {
        fatalError("No SendGrid api key found.")
    }
    let sendGridConfig = SendGridConfig(apiKey: sendGridAPIKey)
    services.register(sendGridConfig)
    let router = EngineRouter.default()
    try routes(router)
    services.register(router, as: Router.self)
    var middlewares = MiddlewareConfig()
    middlewares.use(FileMiddleware.self)
    middlewares.use(ErrorMiddleware.self)
    // This register the sessions middleware as a global middleware
    // it also enabled sessions for all requests
    middlewares.use(SessionsMiddleware.self)
    services.register(middlewares)
    // Configure a database
    var databases = DatabasesConfig()
    
    // This is added for testing
    let hostname = Environment.get("DATABASE_HOSTNAME") ?? "localhost"
    let username = Environment.get("DATABASE_USER") ?? "vapor"
    let password = Environment.get("DATABASE_PASSWORD") ?? "password"
    let databaseName: String
    let databasePort: Int
    if env == .testing {
        databaseName = "vapor-test"
        if let testPort = Environment.get("DATABASE_PORT") {
            databasePort = Int(testPort) ?? 5433
        } else {
            databasePort = 5433
        }
    } else {
        databaseName = Environment.get("DATABASE_DB") ?? "vapor"
        databasePort = 5432
    }
    let databaseConfig = PostgreSQLDatabaseConfig(
        hostname: hostname,
        port: databasePort,
        username: username,
        database: databaseName,
        password: password)
    let database = PostgreSQLDatabase(config: databaseConfig)
    databases.add(database: database, as: .psql)
    services.register(databases)
    var migrations = MigrationConfig()
    // Because we set up a foreign key constraint between acronym.userId and User.id
    // we must create the User table first
    migrations.add(migration: UserType.self, database: .psql) // p.441 using Enums
    migrations.add(model: User.self, database: .psql)
    migrations.add(model: Acronym.self, database: .psql)
    migrations.add(model: Category.self, database: .psql)
    migrations.add(model: AcronymCategoryPivot.self, database: .psql)
    migrations.add(model: Token.self, database: .psql)
    switch env {
    case .development, .testing:
        // Only add adming user if using development/testing environment
        migrations.add(migration: AdminUser.self, database: .psql)
    default:
        break
    }
    migrations.add(model: ResetPasswordToken.self, database: .psql)
//    migrations.add(migration: AddTwitterURLToUser.self, database: .psql)
//    migrations.add(migration: MakeCategoriesUnique.self, database: .psql)
    services.register(migrations)
    
    // Added so that we can revert migrations (used for testing to clear the db, see UserTests.swift)
    var commandConfig = CommandConfig.default()
    commandConfig.useFluentCommands()
    services.register(commandConfig)
    
    // This tells Vapor to use LeafRenderer when asked for a ViewRenderer type.
    config.prefer(LeafRenderer.self, for: ViewRenderer.self)
    // This tells your application to use MemoryKeyedCache when asked for the KeyedCache service.
    // The KeyedCache service is a key-value cache that backs sessions.
    config.prefer(MemoryKeyedCache.self, for: KeyedCache.self)
}

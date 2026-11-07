import Foundation
import SwiftData

enum CushnMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [CushnSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum CushnPersistence {
    /// The on-disk location of user data. Local only: CloudKit is explicitly disabled.
    static func defaultStoreURL() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        return directory.appendingPathComponent("Cushn.store")
    }

    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: CushnSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: CushnMigrationPlan.self, configurations: configuration)
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: CushnSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: CushnMigrationPlan.self, configurations: configuration)
    }
}

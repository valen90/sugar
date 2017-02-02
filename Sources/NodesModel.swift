import Vapor
import Fluent
import Foundation

public protocol NodesModel: Model {
    var created_at: Date? { set get }
    var updated_at: Date? { set get }
    var deleted_at: Date? { set get }
    
    static var softDeletable: Bool { get }
}

extension NodesModel {
    var deleted_at: Date? {
        return nil
    }
    
    static var softDeletable: Bool {
        return true
    }
}

extension NodesModel {
    //FIXME(Brett): not going to get called until Vapor fixes it
    public mutating func willCreate() {
        created_at = Date()
        updated_at = Date()
    }
    
    //FIXME(Brett): not going to get called until Vapor fixes it
    public mutating func willUpdate() {
        updated_at = Date()
    }
    
    public mutating func save() throws {
        let now = Date()
        
        if created_at == nil {
            created_at = now
        }
        
        updated_at = now
        
        try Self.query().save(&self)
    }
    
    public mutating func delete() throws {
        if Self.softDeletable {
            deleted_at = Date()
            try save()
        } else {
            try Self.query().delete(self)
        }
    }
}

extension NodesModel {
    public static func find(_ id: NodeRepresentable) throws -> Self? {
        guard let idKey = database?.driver.idKey else {
            return nil
        }
        
        var query = try Self.query().filter(idKey, .equals, id)
        if Self.softDeletable {
            query = try query.filter("deleted_at", .equals, Node.null)
        }
        
        return try query.first()
    }
    
    public static func all() throws -> [Self] {
        var query = try Self.query()
        if Self.softDeletable {
            query = try query.filter("deleted_at", .equals, Node.null)
        }
        
        return try query.all()
    }
}

extension Query where T: NodesModel {
    public func first() throws -> T? {
        let query = self
        query.action = .fetch
        query.limit = Limit(count: 1)
        
        if T.softDeletable {
            query.filters = [
                Filter(T.self, .compare("deleted_at", .equals, Node.null))
            ]
        }
        
        var model = try query.run().first
        model?.exists = true
        
        return model
    }
    
    public func all() throws -> [T] {
        let query = self
        query.action = .fetch
        
        if T.softDeletable {
            query.filters = [
                Filter(T.self, .compare("deleted_at", .equals, Node.null))
            ]
        }
        
        let models = try query.run()
        models.forEach { model in
            var model = model
            model.exists = true
        }
        
        return models
    }
    
    
    @discardableResult
    public func run() throws -> [T] {
        var models: [T] = []
        
        // filter out soft-deleted models on fetch and count queries
        if action == .fetch || action == .count, T.softDeletable {
            let filter = Filter(T.self, .compare("deleted_at", .equals, Node.null))
            filters.append(filter)
        }
        
        if case .array(let array) = try raw() {
            for result in array {
                do {
                    var model = try T(node: result)
                    if case .object(let dict) = result {
                        model.id = dict["id"]
                    }
                    models.append(model)
                } catch {
                    print("Could not initialize \(T.self), skipping: \(error)")
                }
            }
        } else {
            print("Unsupported Node type, only array is supported.")
        }
        
        return models
    }
}

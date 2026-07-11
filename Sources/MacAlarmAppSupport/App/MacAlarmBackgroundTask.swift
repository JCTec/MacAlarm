import Foundation

enum MacAlarmBackgroundTask {
    static func value<T: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () -> T
    ) async -> T {
        let worker = Task.detached(priority: priority, operation: operation)
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    static func throwing<T: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let worker = Task.detached(priority: priority) {
            try operation()
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

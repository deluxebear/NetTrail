import Foundation

/// Served by the filter extension on its NEMachServiceName; the app pulls event batches.
@objc public protocol TraceFilterXPC {
    /// Replies with `EventBatch.encoded()` holding at most `maxCount` events.
    func fetchEvents(maxCount: Int, reply: @escaping @Sendable (Data) -> Void)
}

public enum TraceXPC {
    /// Code-signing requirement matching any code signed by `teamID`.
    public static func requirement(teamID: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

public enum PeekResult: Equatable, Sendable {
    case found(String)
    case needMore
    case notFound
}

public enum SniffResult: Equatable, Sendable {
    case found(host: String, source: HostSource)
    case needMore
    case notFound
}

import Foundation
import NetworkExtension
import os
import TraceCore

/// Monitor-only content filter: every path returns allow.
final class FilterDataProvider: NEFilterDataProvider {
    private static let peekTimeout: TimeInterval = 2
    private static let dnsPeekBytes = 1500

    private let ring = EventRing(capacity: 10_000)
    private let dnsCache = DNSCache()
    private let identities = IdentityCache()
    private let peeks = PeekTable()
    private let counters = FlowCounters()
    private var server: EventServer?
    private var sweepTimer: DispatchSourceTimer?
    private let log = Logger(subsystem: "com.xiongyanlin.trace.filter", category: "filter")

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        server = EventServer(ring: ring)
        if server == nil { log.error("missing NEMachServiceName/TraceTeamID; XPC disabled") }
        server?.start()
        startSweeper()
        apply(NEFilterSettings(rules: [], defaultAction: .filterData)) { error in
            if let error { self.log.error("apply settings failed: \(error.localizedDescription, privacy: .public)") }
            completionHandler(error)
        }
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        sweepTimer?.cancel()
        sweepTimer = nil
        server?.stop()
        server = nil
        completionHandler()
    }

    // MARK: Flows

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socketFlow = flow as? NEFilterSocketFlow, let remote = RemoteEndpoint.of(socketFlow) else {
            return .allow()
        }
        if remote.proto == .udp && remote.port == 53 {
            // DNS responses feed the IP → name cache; DNS flows themselves are not recorded.
            return .filterDataVerdict(withFilterInbound: true, peekInboundBytes: Self.dnsPeekBytes,
                                      filterOutbound: false, peekOutboundBytes: 0)
        }
        let source = identities.source(for: flow.sourceAppAuditToken ?? socketFlow.sourceProcessAuditToken)
        let now = Date()
        let pending = PendingOpen(app: source.identity, origin: source.origin, remote: remote, startedAt: now)
        if let host = HostNormalizer.normalizeDomain(socketFlow.remoteHostname) {
            emit(flow.identifier, pending, host: host, source: .system)
            return Self.allowAndReport()
        }
        guard remote.proto == .tcp else {
            emitFallback(flow.identifier, pending, now: now)
            return Self.allowAndReport()
        }
        peeks.begin(flow.identifier, pending)
        let verdict = NEFilterNewFlowVerdict.filterDataVerdict(
            withFilterInbound: false, peekInboundBytes: 0,
            filterOutbound: true, peekOutboundBytes: PayloadSniffer.maxPeekBytes)
        verdict.shouldReport = true
        verdict.statisticsReportFrequency = Self.statisticsFrequency
        return verdict
    }

    override func handleOutboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        guard let pending = peeks.append(flow.identifier, readBytes) else { return Self.dataAllowAndReport() }
        let now = Date()
        switch PayloadSniffer.sniff(pending.buffer) {
        case let .found(host, source):
            if let taken = peeks.take(flow.identifier) {
                emit(flow.identifier, taken, host: host, source: source)
            }
            return Self.dataAllowAndReport()
        case .needMore where pending.buffer.count < PayloadSniffer.maxPeekBytes
            && now.timeIntervalSince(pending.startedAt) < Self.peekTimeout:
            let verdict = NEFilterDataVerdict(passBytes: readBytes.count, peekBytes: PayloadSniffer.maxPeekBytes)
            verdict.statisticsReportFrequency = Self.statisticsFrequency
            return verdict
        default:
            if let taken = peeks.take(flow.identifier) { emitFallback(flow.identifier, taken, now: now) }
            return Self.dataAllowAndReport()
        }
    }

    override func handleOutboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        if let taken = peeks.take(flow.identifier) { emitFallback(flow.identifier, taken, now: Date()) }
        return Self.dataAllowAndReport()
    }

    override func handleInboundData(from flow: NEFilterFlow, readBytesStartOffset offset: Int, readBytes: Data) -> NEFilterDataVerdict {
        if let answer = DNSResponseParser.parse(readBytes) {
            let now = Date()
            for address in answer.addresses {
                dnsCache.insert(ip: address.ip, host: answer.queryName, ttl: address.ttl, now: now)
            }
        }
        return NEFilterDataVerdict(passBytes: readBytes.count, peekBytes: Self.dnsPeekBytes)
    }

    override func handleInboundDataComplete(for flow: NEFilterFlow) -> NEFilterDataVerdict {
        .allow()
    }

    /// Statistics reports carry the flow's running byte totals; they are turned into increments here.
    override func handle(_ report: NEFilterReport) {
        guard let flow = report.flow, report.event == .statistics || report.event == .flowClosed else { return }
        let now = Date()
        // A flow can report traffic before its hostname peek finishes; its “opened” event must come first.
        if let taken = peeks.take(flow.identifier) { emitFallback(flow.identifier, taken, now: now) }
        let totalIn = UInt64(max(0, report.bytesInboundCount))
        let totalOut = UInt64(max(0, report.bytesOutboundCount))
        if report.event == .statistics {
            let delta = counters.advance(flow.identifier, totalIn: totalIn, totalOut: totalOut)
            guard !delta.isZero else { return }
            ring.append(.progress(FlowProgress(flowID: flow.identifier, time: now,
                                               bytesIn: delta.bytesIn, bytesOut: delta.bytesOut)))
        } else {
            let rest = counters.finish(flow.identifier, totalIn: totalIn, totalOut: totalOut)
            ring.append(.closed(FlowClosed(flowID: flow.identifier, time: now,
                                           bytesIn: rest.bytesIn, bytesOut: rest.bytesOut)))
        }
    }

    // MARK: Helpers

    /// About once a second, so long-lived flows show traffic while they run.
    private static let statisticsFrequency: NEFilterReport.Frequency = .medium

    private static func allowAndReport() -> NEFilterNewFlowVerdict {
        let verdict = NEFilterNewFlowVerdict.allow()
        verdict.shouldReport = true
        verdict.statisticsReportFrequency = statisticsFrequency
        return verdict
    }

    private static func dataAllowAndReport() -> NEFilterDataVerdict {
        let verdict = NEFilterDataVerdict.allow()
        verdict.shouldReport = true
        verdict.statisticsReportFrequency = statisticsFrequency
        return verdict
    }

    private func emit(_ id: UUID, _ pending: PendingOpen, host: String?, source: HostSource) {
        ring.append(.opened(FlowOpened(flowID: id, time: pending.startedAt, app: pending.app, origin: pending.origin,
                                       remote: pending.remote, host: host, hostSource: source)))
    }

    private func emitFallback(_ id: UUID, _ pending: PendingOpen, now: Date) {
        if let host = dnsCache.lookup(ip: pending.remote.ip, now: now) {
            emit(id, pending, host: host, source: .dnsCache)
        } else {
            emit(id, pending, host: nil, source: .none)
        }
    }

    /// Emits fallback “opened” events for flows that never sent enough bytes within the timeout.
    private func startSweeper() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.xiongyanlin.trace.filter.sweep"))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            for (id, pending) in self.peeks.takeExpired(startedBefore: now.addingTimeInterval(-Self.peekTimeout)) {
                self.emitFallback(id, pending, now: now)
            }
        }
        timer.resume()
        sweepTimer = timer
    }
}

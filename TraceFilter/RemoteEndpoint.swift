import Network
import NetworkExtension
import TraceCore

enum RemoteEndpoint {
    /// Remote IP/port/protocol of a socket flow, or nil for non-IP or non-TCP/UDP flows.
    static func of(_ flow: NEFilterSocketFlow) -> Endpoint? {
        let proto: TransportProtocol
        switch flow.socketProtocol {
        case IPPROTO_TCP: proto = .tcp
        case IPPROTO_UDP: proto = .udp
        default: return nil
        }
        var hostText: String?
        var port: UInt16?
        if #available(macOS 15, *) {
            if case let .hostPort(host, p)? = flow.remoteFlowEndpoint {
                hostText = "\(host)"
                port = p.rawValue
            }
        } else if let endpoint = flow.remoteEndpoint as? NWHostEndpoint {
            hostText = endpoint.hostname
            port = UInt16(endpoint.port)
        }
        guard let hostText, let port, let ip = IPAddressText.normalize(hostText) else { return nil }
        return Endpoint(ip: ip, port: port, proto: proto)
    }
}

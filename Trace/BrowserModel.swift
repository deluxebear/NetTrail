import Foundation
import TraceKit

@MainActor
final class BrowserModel: ObservableObject {
    enum SidebarItem: Hashable {
        case allApps
        case app(Int64)
        case settings
    }

    enum AppSort: String, CaseIterable, Identifiable {
        case recent, traffic
        var id: String { rawValue }
        var title: String { self == .recent ? "最近" : "流量" }
    }

    @Published var selection: SidebarItem? = .allApps {
        didSet { if oldValue != selection { selectedDomain = nil; reload() } }
    }
    @Published var range: TimeRange = .today { didSet { reload() } }
    @Published var appSort: AppSort = .recent { didSet { reload() } }
    @Published var search = ""
    @Published var selectedDomain: String? { didSet { reloadDetail() } }
    @Published private(set) var apps: [AppSummary] = []
    @Published private(set) var domains: [DomainSummary] = []
    @Published private(set) var detailHours: [HourPoint] = []
    @Published private(set) var detailApps: [AppSummary] = []
    @Published private(set) var detailOrigins: [OriginSummary] = []
    @Published private(set) var errorText: String?

    private let store: Store

    init(store: Store) {
        self.store = store
    }

    var filteredApps: [AppSummary] {
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(search) || $0.key.localizedCaseInsensitiveContains(search)
        }
    }

    var selectedAppID: Int64? {
        if case .app(let id) = selection { return id }
        return nil
    }

    var selectedApp: AppSummary? {
        selectedAppID.flatMap { id in apps.first { $0.id == id } }
    }

    /// Display names shared by more than one app (e.g. several `node` installs), which need a location hint.
    var ambiguousNames: Set<String> {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for app in apps where !seen.insert(app.displayName).inserted { duplicates.insert(app.displayName) }
        return duplicates
    }

    /// Proxy rules for the hosts `appID` contacted in the current time range, without LAN addresses.
    func proxyRules(appID: Int64, format: ProxyRuleFormat) -> String {
        do {
            return ProxyRules.render(try store.domains(appID: appID, range: range).map(\.domain), as: format)
        } catch {
            errorText = error.localizedDescription
            return ""
        }
    }

    func reload() {
        do {
            var loaded = try store.apps(range: range)
            if appSort == .traffic {
                loaded.sort { $0.bytesIn &+ $0.bytesOut > $1.bytesIn &+ $1.bytesOut }
            }
            update(\.apps, loaded)
            switch selection {
            case .app(let id): update(\.domains, try store.domains(appID: id, range: range))
            case .allApps: update(\.domains, try store.domains(appID: nil, range: range))
            case .settings, nil: update(\.domains, [])
            }
            update(\.errorText, nil)
        } catch {
            errorText = "读取数据失败：\(error.localizedDescription)"
        }
        reloadDetail()
    }

    func focus(appKey: String) {
        if let app = (try? store.apps(range: .all))?.first(where: { $0.key == appKey }) {
            selection = .app(app.id)
        }
    }

    private func reloadDetail() {
        do {
            if selectedDomain != nil || selectedAppID != nil {
                update(\.detailOrigins, try store.origins(appID: selectedAppID, domain: selectedDomain, range: range))
            } else {
                update(\.detailOrigins, [])
            }
            guard let domain = selectedDomain else {
                update(\.detailHours, [])
                update(\.detailApps, [])
                return
            }
            update(\.detailHours, try store.hourly(appID: selectedAppID, domain: domain,
                                                   since: Date().addingTimeInterval(-7 * 86_400)))
            update(\.detailApps, selectedAppID == nil ? try store.apps(range: range, domain: domain) : [])
        } catch {
            errorText = "读取数据失败：\(error.localizedDescription)"
        }
    }

    /// Reloads run every few seconds while traffic flows; skip unchanged values so tables are not re-laid out.
    private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<BrowserModel, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}

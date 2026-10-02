import Foundation
import TraceKit

/// Looks for a newer NetTrail release on GitHub: once at launch, then daily.
/// Only the public releases endpoint is contacted, and no data about the user is sent.
@MainActor
final class UpdateChecker: ObservableObject {
    static let enabledKey = "checkForUpdates"
    private static let endpoint = URL(string: "https://api.github.com/repos/deluxebear/NetTrail/releases/latest")!

    @Published private(set) var available: AvailableUpdate?
    private var started = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    func start() {
        guard !started else { return }
        started = true
        Task {
            while !Task.isCancelled {
                await check()
                try? await Task.sleep(for: .seconds(86_400))
            }
        }
    }

    func check() async {
        guard Self.isEnabled,
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else { available = nil; return }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return }   // offline or rate-limited: keep whatever we knew
        available = UpdateCheck.newerRelease(current: current, json: data)
    }
}

import Foundation
import UIKit
import Combine

@MainActor
final class AppVersionGateManager: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateRequired(latestVersion: String, storeURL: URL)
    }

    @Published private(set) var state: State

    private var hasCheckedThisLaunch: Bool
    private var checkTask: Task<Void, Never>?

    init(initialState: State = .idle) {
        state = initialState
        hasCheckedThisLaunch = initialState != .idle
    }

    var shouldBlockLaunch: Bool {
        if case .updateRequired = state { return true }
        return state == .checking
    }

    func checkIfNeeded(force: Bool = false) {
        if !force, hasCheckedThisLaunch { return }
        hasCheckedThisLaunch = true
        runCheck()
    }

    func recheckNow() {
        runCheck()
    }

    func openUpdate() {
        guard case let .updateRequired(_, storeURL) = state else { return }
        UIApplication.shared.open(storeURL)
    }

    private func runCheck() {
        checkTask?.cancel()
        state = .checking
        checkTask = Task {
            do {
                let result = try await fetchLatestVersion()
                if isRemoteVersionNewer(local: AppInfo.version, remote: result.latestVersion) {
                    state = .updateRequired(latestVersion: result.latestVersion, storeURL: result.storeURL)
                } else {
                    state = .upToDate
                }
            } catch {
                // Do not block launch if check fails (offline/API issue).
                state = .upToDate
            }
        }
    }

    private func fetchLatestVersion() async throws -> (latestVersion: String, storeURL: URL) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.alexmalaimare.practicebuddy"
        guard var components = URLComponents(string: "https://itunes.apple.com/lookup") else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleID),
            URLQueryItem(name: "country", value: Locale.current.region?.identifier ?? "us")
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 6

        let (data, _) = try await URLSession.shared.data(for: request)
        let lookup = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        guard
            let app = lookup.results.first,
            !app.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw URLError(.cannotParseResponse)
        }
        let fallback = URL(string: "https://apps.apple.com/app/id\(AppInfo.appStoreAppleID)") ?? URL(string: "https://apps.apple.com")!
        return (app.version, app.trackViewUrl ?? fallback)
    }

    private func isRemoteVersionNewer(local: String, remote: String) -> Bool {
        let lhs = versionComponents(local)
        let rhs = versionComponents(remote)
        let maxCount = max(lhs.count, rhs.count)
        for idx in 0..<maxCount {
            let l = idx < lhs.count ? lhs[idx] : 0
            let r = idx < rhs.count ? rhs[idx] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    private func versionComponents(_ raw: String) -> [Int] {
        raw
            .split(separator: ".")
            .map { part in Int(part.filter(\.isNumber)) ?? 0 }
    }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreLookupItem]
}

private struct AppStoreLookupItem: Decodable {
    let version: String
    let trackViewUrl: URL?
}

import Foundation
import UIKit

enum AppInfo {
    static let appStoreAppleID = "6759354312"

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "PracticeBuddy"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var versionBuildString: String {
        "\(version) (\(build))"
    }

    static var deviceString: String {
        let d = UIDevice.current
        return "\(d.model) • iOS \(d.systemVersion)"
    }

    static var supportInfo: String {
        """
        \(appName)
        Version: \(versionBuildString)
        Device: \(deviceString)
        """
    }

    static var feedbackTemplate: String {
        """
        \(appName) Feedback

        Version: \(versionBuildString)
        Device: \(deviceString)

        What happened?
        - 

        What did you expect?
        - 

        Steps to reproduce (if any):
        - 
        """
    }

    static var inviteLinkBaseURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PBInviteLinkBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" {
                return url
            }
        }
        if let fallback = URL(string: "https://practicebuddytracker.web.app") {
            return fallback
        }
        return nil
    }

    static func buddyInviteURL(friendCode: String) -> URL? {
        guard let friendCode = IncomingLinkParser.normalizedFriendCode(friendCode),
              let baseURL = inviteLinkBaseURL else {
            return nil
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent("invite"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "code", value: friendCode)]
        return components?.url
    }

    static var privacyPolicyURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PBPrivacyPolicyURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" {
                return url
            }
        }
        return nil
    }

    static var termsOfUseURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PBTermsOfUseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" {
                return url
            }
        }
        if let fallback = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
            return fallback
        }
        return nil
    }

    static var duelFunctionsBaseURL: URL? {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "PBDuelFunctionsBaseURL") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), scheme == "https" {
                return url
            }
        }

        if let fallback = URL(string: "https://us-central1-practicebuddytracker.cloudfunctions.net") {
            return fallback
        }
        return nil
    }

    static var masterEmails: Set<String> {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PBMasterEmails") as? [String] else {
            return []
        }
        return Set(
            raw
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
    }

    static var masterUIDs: Set<String> {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PBMasterUIDs") as? [String] else {
            return []
        }
        return Set(
            raw
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func isMasterAccount(uid: String?, email: String?) -> Bool {
        if let uid, !uid.isEmpty, masterUIDs.contains(uid) {
            return true
        }
        if let email {
            let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty, masterEmails.contains(normalized) {
                return true
            }
        }
        return false
    }

    static var isTestFlightBuild: Bool {
        if let receiptURL = Bundle.main.value(forKey: "appStoreReceiptURL") as? URL {
            if receiptURL.lastPathComponent.lowercased() == "sandboxreceipt" {
                return true
            }
        }
        return boolValue(for: "PBIsTestFlightBuild", defaultValue: false)
    }

    private static func stringValue(for key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func boolValue(for key: String, defaultValue: Bool) -> Bool {
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? Bool {
            return value
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes", "on"].contains(normalized) { return true }
            if ["0", "false", "no", "off"].contains(normalized) { return false }
        }
        return defaultValue
    }
}

enum IncomingLinkAction: Equatable {
    case addBuddy(friendCode: String)
    case openPracticeStudio
}

enum IncomingLinkParser {
    private static let canonicalInviteHost = "practicebuddytracker.web.app"

    static func action(
        from url: URL,
        trustedInviteHosts: Set<String> = [canonicalInviteHost]
    ) -> IncomingLinkAction? {
        let scheme = url.scheme?.lowercased()
        let host = url.host?.lowercased()

        if scheme == "practicebuddy", host == "practice" {
            return .openPracticeStudio
        }

        if scheme == "practicebuddy", host == "add-buddy",
           let code = inviteCode(from: url) {
            return .addBuddy(friendCode: code)
        }

        guard scheme == "https",
              let host,
              trustedInviteHosts.map({ $0.lowercased() }).contains(host),
              normalizedPath(url.path) == "/invite",
              let code = inviteCode(from: url) else {
            return nil
        }
        return .addBuddy(friendCode: code)
    }

    static func normalizedFriendCode(_ rawCode: String) -> String? {
        let code = rawCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard code.range(
            of: #"^[A-Z0-9]{4}-[A-Z0-9]{4}$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return code
    }

    private static func inviteCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = components.queryItems?
                .first(where: { $0.name.lowercased() == "code" })?
                .value else {
            return nil
        }
        return normalizedFriendCode(value)
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/\(trimmed.lowercased())"
    }
}

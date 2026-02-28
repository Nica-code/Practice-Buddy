import Foundation
import UIKit

enum AppInfo {
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
}

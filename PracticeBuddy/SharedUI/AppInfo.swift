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
}

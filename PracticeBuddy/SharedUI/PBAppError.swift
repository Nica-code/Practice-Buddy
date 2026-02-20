import Foundation

/// A lightweight, user-presentable error for SwiftUI alerts.
struct PBAppError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

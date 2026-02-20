import Foundation
import SwiftData
import Combine

@MainActor
protocol SocialProvider: ObservableObject {
    var providerName: String { get }
    var isSignedIn: Bool { get }

    var totals: SocialTotals { get }
    var lastRefresh: Date? { get }

    func configure(modelContext: ModelContext)
    func refresh()

    func shareText(for period: SocialPeriod) -> String
    func shareImageURL(for period: SocialPeriod) -> URL?
}

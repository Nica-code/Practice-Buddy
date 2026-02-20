import SwiftUI

/// Lazily builds a destination view. Helpful for TabView + NavigationStack to avoid
/// initializing heavy views (and any timers) before the user opens that tab.
struct PBLazyView<Content: View>: View {
    private let build: () -> Content

    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }

    var body: some View {
        build()
    }
}

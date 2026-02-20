import SwiftUI

/// Small helper so numeric text looks stable (no digit width jitter).
extension View {
    func pbMonospacedDigits() -> some View {
        self.monospacedDigit()
    }
}

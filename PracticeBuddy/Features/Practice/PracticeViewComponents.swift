import SwiftUI

struct PracticeSaveSheetView: View {
    let currentElapsedSeconds: Int
    @Binding var notes: String
    let onDiscard: () -> Void
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    Text(L10n.f("Duration: %@", DurationFormatter.string(from: currentElapsedSeconds)))
                }
                Section("Notes (optional)") {
                    TextField("What did you practice?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Save Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        onDiscard()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                    .disabled(currentElapsedSeconds == 0)
                    .accessibilityHint(Text("Saves this practice session to history"))
                }
            }
        }
    }
}

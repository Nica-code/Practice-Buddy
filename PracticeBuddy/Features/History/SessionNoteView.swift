import SwiftUI
import os

struct SessionNoteView: View {
    @EnvironmentObject private var store: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.pbTheme) private var theme
    @Environment(\.pbTypography) private var type

    let sessionID: UUID

    @State private var draftNotes: String = ""
    @State private var didLoad = false
    @State private var showSaved = false

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PracticeBuddy",
                                category: "session-note")

    var body: some View {
        NavigationStack {
            Group {
                if let session = store.sessions.first(where: { $0.id == sessionID }) {
                    content(for: session)
                } else {
                    Text("Session not found.")
                        .foregroundStyle(theme.textSecondary)
                        .padding()
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Session Journal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .font(type.button)
                }

                if usesLegacyEditor {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveTapped()
                        }
                        .font(type.button)
                        .disabled(!canSave)
                    }
                }
            }
            .onAppear {
                if !didLoad {
                    didLoad = true
                    draftNotes = initialNotes()
                }
            }
            .alert("Saved", isPresented: $showSaved) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Your notes were updated.")
            }
        }
    }

    @ViewBuilder
    private func content(for session: PracticeSessionModel) -> some View {
        if let journal = session.journal {
            Form {
                if !session.noteTitle.isEmpty || !session.noteFocus.isEmpty || !session.noteMoodRaw.isEmpty {
                    Section("Header") {
                        if !session.noteTitle.isEmpty {
                            Text(session.noteTitle)
                                .font(type.sectionTitle)
                                .foregroundStyle(theme.textPrimary)
                        }
                        if !session.noteFocus.isEmpty {
                            Text("Focus: \(session.noteFocus)")
                                .font(type.body)
                                .foregroundStyle(theme.textSecondary)
                        }
                        if let mood = PracticeNoteMood(rawValue: session.noteMoodRaw) {
                            Text("Mood: \(mood.title)")
                                .font(type.body)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    .listRowBackground(theme.surface)
                }

                if !journal.pieces.isEmpty {
                    Section("Pieces") {
                        ForEach(journal.pieces) { piece in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(piece.title.isEmpty ? "Piece" : piece.title)
                                    .font(type.sectionTitle)
                                    .foregroundStyle(theme.textPrimary)

                                if !piece.tempo.isEmpty {
                                    Text("Tempo: \(piece.tempo)")
                                        .font(type.footnote)
                                        .foregroundStyle(theme.textSecondary)
                                }
                                if !piece.wentWell.isEmpty {
                                    Text(.init("**Went well**\n\(piece.wentWell)"))
                                        .font(type.body)
                                        .foregroundStyle(theme.textPrimary)
                                }
                                if !piece.needsWork.isEmpty {
                                    Text(.init("**Needs work**\n\(piece.needsWork)"))
                                        .font(type.body)
                                        .foregroundStyle(theme.textPrimary)
                                }
                                if !piece.nextAction.isEmpty {
                                    Text(.init("**Next action**\n\(piece.nextAction)"))
                                        .font(type.body)
                                        .foregroundStyle(theme.textPrimary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowBackground(theme.surface)
                }

                if !journal.reflection.isEmpty {
                    Section("Reflection") {
                        Text(.init(journal.reflection))
                            .font(type.body)
                            .foregroundStyle(theme.textPrimary)
                    }
                    .listRowBackground(theme.surface)
                }
            }
        } else {
            Form {
                Section("Notes") {
                    TextEditor(text: $draftNotes)
                        .font(type.body)
                        .frame(minHeight: 180)
                }
                .listRowBackground(theme.surface)

                Section {
                    Text("\(draftNotes.count) characters")
                        .font(type.footnote)
                        .foregroundStyle(theme.textSecondary)
                }
                .listRowBackground(theme.surface)
            }
        }
    }

    private var usesLegacyEditor: Bool {
        let session = store.sessions.first(where: { $0.id == sessionID })
        return session?.journal == nil
    }

    private var canSave: Bool {
        // Allow empty notes too, but prevent saving if it didn’t change anything.
        draftNotes != initialNotes()
    }

    private func initialNotes() -> String {
        store.sessions.first(where: { $0.id == sessionID })?.notes ?? ""
    }

    private func saveTapped() {
        let trimmed = draftNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        store.updateNotes(for: sessionID, notes: trimmed)
        logger.debug("Saved notes for session \(self.sessionID.uuidString, privacy: .public)")
        showSaved = true
    }
}

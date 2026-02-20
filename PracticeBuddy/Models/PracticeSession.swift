//
//  PracticeSession.swift
//  PracticeBuddy
//
//  Created by Nica on 1/26/26.
//
import Foundation

struct PracticeSession: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let durationSeconds: Int
    let notes: String
    let noteTitle: String
    let noteFocus: String
    let noteMoodRaw: String
    let noteStructuredJSON: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        durationSeconds: Int,
        notes: String,
        noteTitle: String = "",
        noteFocus: String = "",
        noteMoodRaw: String = "",
        noteStructuredJSON: String = ""
    ) {
        self.id = id
        self.date = date
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.noteTitle = noteTitle
        self.noteFocus = noteFocus
        self.noteMoodRaw = noteMoodRaw
        self.noteStructuredJSON = noteStructuredJSON
    }
}

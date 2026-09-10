//
//  UniversalQuestionBank.swift
//  DailyJournal
//
//  The fixed 50 universal questions. Always available, no network required.
//  Live consumer today: Chat's offline fallback (AIService+Chat.localNextTurn)
//  picks one when Gemini is unavailable.
//
//  Used to also feed a Question Bank / panel system (categories, mode
//  suitability, personal levels, card conversion) that was cut — the panel was
//  unreachable UI. This is now just questions, kept as plain text + tags.
//
//  Categories, for reference (no longer modeled as a type, just grouping below):
//   • blank    — blank-page friendly (UQ001–UQ010)
//   • body     — body, energy, and mood (UQ011–UQ020)
//   • people   — people and messages (UQ021–UQ030)
//   • work     — work, pressure, and avoidance (UQ031–UQ040)
//   • home     — home, world, and tiny details (UQ041–UQ050)
//

import Foundation

enum UniversalQuestionBank {

    // MARK: - All 50 questions

    static let all: [UniversalQuestion] = blankPage + body + people + work + home

    // MARK: - Blank-page friendly (UQ001–UQ010)

    static let blankPage: [UniversalQuestion] = [
        UniversalQuestion(id: "UQ001", text: "What part of today is easiest to tell?", tags: ["blank"]),
        UniversalQuestion(id: "UQ002", text: "What did today feel like in one small scene?", tags: ["blank"]),
        UniversalQuestion(id: "UQ003", text: "What was the first moment you noticed yourself today?", tags: ["blank"]),
        UniversalQuestion(id: "UQ004", text: "What happened today that someone else might not have seen?", tags: ["blank"]),
        UniversalQuestion(id: "UQ005", text: "What made today feel like today?", tags: ["blank"]),
        UniversalQuestion(id: "UQ006", text: "What is the smallest true thing about today?", tags: ["blank"]),
        UniversalQuestion(id: "UQ007", text: "What did you keep carrying from one hour into the next?", tags: ["blank", "work"]),
        UniversalQuestion(id: "UQ008", text: "Where did the day slow down for you?", tags: ["blank"]),
        UniversalQuestion(id: "UQ009", text: "What felt unfinished when the day ended?", tags: ["blank", "work"]),
        UniversalQuestion(id: "UQ010", text: "If today had a texture, where did you feel it?", tags: ["blank", "body"])
    ]

    // MARK: - Body, energy, and mood (UQ011–UQ020)

    static let body: [UniversalQuestion] = [
        UniversalQuestion(id: "UQ011", text: "What did your body ask for today?", tags: ["body"]),
        UniversalQuestion(id: "UQ012", text: "When did your energy change?", tags: ["body"]),
        UniversalQuestion(id: "UQ013", text: "What felt heavier than expected?", tags: ["body"]),
        UniversalQuestion(id: "UQ014", text: "What felt lighter than expected?", tags: ["body"]),
        UniversalQuestion(id: "UQ015", text: "What did rest look like today, even briefly?", tags: ["body", "sleep"]),
        UniversalQuestion(id: "UQ016", text: "What did movement change in your mood?", tags: ["body", "moved"]),
        UniversalQuestion(id: "UQ017", text: "What did you eat, skip, crave, or notice?", tags: ["body", "food"]),
        UniversalQuestion(id: "UQ018", text: "What part of the day did your body remember most?", tags: ["body"]),
        UniversalQuestion(id: "UQ019", text: "When did you feel most awake?", tags: ["body", "sleep"]),
        UniversalQuestion(id: "UQ020", text: "What did tiredness make harder?", tags: ["body", "sleep"])
    ]

    // MARK: - People and messages (UQ021–UQ030)

    static let people: [UniversalQuestion] = [
        UniversalQuestion(id: "UQ021", text: "Who affected the shape of your day?", tags: ["people"]),
        UniversalQuestion(id: "UQ022", text: "What conversation stayed with you?", tags: ["people", "messages"]),
        UniversalQuestion(id: "UQ023", text: "What did you wish someone understood today?", tags: ["people"]),
        UniversalQuestion(id: "UQ024", text: "What message changed your mood a little?", tags: ["people", "messages"]),
        UniversalQuestion(id: "UQ025", text: "What did you say yes to, and how did it feel?", tags: ["people"]),
        UniversalQuestion(id: "UQ026", text: "What did you not say out loud?", tags: ["people", "avoided"]),
        UniversalQuestion(id: "UQ027", text: "Where did you feel connected, even briefly?", tags: ["people"]),
        UniversalQuestion(id: "UQ028", text: "Where did you feel far away from people?", tags: ["people"]),
        UniversalQuestion(id: "UQ029", text: "What kindness did you receive or miss?", tags: ["people"]),
        UniversalQuestion(id: "UQ030", text: "What did someone do that stayed in your head?", tags: ["people"])
    ]

    // MARK: - Work, pressure, and avoidance (UQ031–UQ040)

    static let work: [UniversalQuestion] = [
        UniversalQuestion(id: "UQ031", text: "What asked the most from you today?", tags: ["work"]),
        UniversalQuestion(id: "UQ032", text: "What did you avoid, and was it trying to protect you?", tags: ["work", "avoided"]),
        UniversalQuestion(id: "UQ033", text: "What task followed you after it ended?", tags: ["work"]),
        UniversalQuestion(id: "UQ034", text: "What felt like progress, even if it was small?", tags: ["work", "tiny win"]),
        UniversalQuestion(id: "UQ035", text: "What decision took more energy than expected?", tags: ["work"]),
        UniversalQuestion(id: "UQ036", text: "What did you finish, pause, or postpone?", tags: ["work"]),
        UniversalQuestion(id: "UQ037", text: "What pressure was real, and what pressure was imagined?", tags: ["work"]),
        UniversalQuestion(id: "UQ038", text: "What part of responsibility felt human today?", tags: ["work"]),
        UniversalQuestion(id: "UQ039", text: "What tiny win deserves a mark?", tags: ["work", "tiny win"]),
        UniversalQuestion(id: "UQ040", text: "Where did you do enough?", tags: ["work"])
    ]

    // MARK: - Home, world, and tiny details (UQ041–UQ050)

    static let home: [UniversalQuestion] = [
        UniversalQuestion(id: "UQ041", text: "What did your space do to your mood today?", tags: ["home"]),
        UniversalQuestion(id: "UQ042", text: "What sound, light, smell, or weather changed the day?", tags: ["home", "outside"]),
        UniversalQuestion(id: "UQ043", text: "What outside thing pulled your attention?", tags: ["home", "outside"]),
        UniversalQuestion(id: "UQ044", text: "What did money make louder or quieter today?", tags: ["home", "money"]),
        UniversalQuestion(id: "UQ045", text: "What did your screen give you, and what did it take?", tags: ["home", "screen"]),
        UniversalQuestion(id: "UQ046", text: "What felt beautiful for half a second?", tags: ["home"]),
        UniversalQuestion(id: "UQ047", text: "What felt annoying but also ordinary?", tags: ["home"]),
        UniversalQuestion(id: "UQ048", text: "What did you wish the day had made room for?", tags: ["home"]),
        UniversalQuestion(id: "UQ049", text: "What should future you know about this day?", tags: ["home", "blank"]),
        UniversalQuestion(id: "UQ050", text: "What question do you wish someone gently asked you today?", tags: ["blank"])
    ]

}

// MARK: - UniversalQuestion model

struct UniversalQuestion: Identifiable, Equatable {
    let id: String
    let text: String
    let tags: [String]
}

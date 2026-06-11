//
//  UniversalQuestionBank.swift
//  DailyJournal
//
//  The fixed 50 universal questions. Always available, no network required,
//  safe for new users. This bank is never removed.
//
//  Questions are organized into 5 categories:
//   • blank    — blank-page friendly (UQ001–UQ010)
//   • body     — body, energy, and mood (UQ011–UQ020)
//   • people   — people and messages (UQ021–UQ030)
//   • work     — work, pressure, and avoidance (UQ031–UQ040)
//   • home     — home, world, and tiny details (UQ041–UQ050)
//
//  Every question is personalLevel = .safe, so all are lock-screen safe.
//

import Foundation

enum UniversalQuestionBank {

    // MARK: - All 50 questions

    static let all: [UniversalQuestion] = blankPage + body + people + work + home

    // MARK: - Blank-page friendly (UQ001–UQ010)

    static let blankPage: [UniversalQuestion] = [
        UniversalQuestion(
            id: "UQ001",
            text: "What part of today is easiest to tell?",
            category: .blank,
            tags: ["blank"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ002",
            text: "What did today feel like in one small scene?",
            category: .blank,
            tags: ["blank"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ003",
            text: "What was the first moment you noticed yourself today?",
            category: .blank,
            tags: ["blank"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ004",
            text: "What happened today that someone else might not have seen?",
            category: .blank,
            tags: ["blank"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ005",
            text: "What made today feel like today?",
            category: .blank,
            tags: ["blank"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ006",
            text: "What is the smallest true thing about today?",
            category: .blank,
            tags: ["blank"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ007",
            text: "What did you keep carrying from one hour into the next?",
            category: .blank,
            tags: ["blank", "work"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ008",
            text: "Where did the day slow down for you?",
            category: .blank,
            tags: ["blank"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ009",
            text: "What felt unfinished when the day ended?",
            category: .blank,
            tags: ["blank", "work"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ010",
            text: "If today had a texture, where did you feel it?",
            category: .blank,
            tags: ["blank", "body"],
            modeSuitability: .write
        )
    ]

    // MARK: - Body, energy, and mood (UQ011–UQ020)

    static let body: [UniversalQuestion] = [
        UniversalQuestion(
            id: "UQ011",
            text: "What did your body ask for today?",
            category: .body,
            tags: ["body"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ012",
            text: "When did your energy change?",
            category: .body,
            tags: ["body"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ013",
            text: "What felt heavier than expected?",
            category: .body,
            tags: ["body"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ014",
            text: "What felt lighter than expected?",
            category: .body,
            tags: ["body"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ015",
            text: "What did rest look like today, even briefly?",
            category: .body,
            tags: ["body", "sleep"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ016",
            text: "What did movement change in your mood?",
            category: .body,
            tags: ["body", "moved"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ017",
            text: "What did you eat, skip, crave, or notice?",
            category: .body,
            tags: ["body", "food"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ018",
            text: "What part of the day did your body remember most?",
            category: .body,
            tags: ["body"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ019",
            text: "When did you feel most awake?",
            category: .body,
            tags: ["body", "sleep"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ020",
            text: "What did tiredness make harder?",
            category: .body,
            tags: ["body", "sleep"],
            modeSuitability: .both
        )
    ]

    // MARK: - People and messages (UQ021–UQ030)

    static let people: [UniversalQuestion] = [
        UniversalQuestion(
            id: "UQ021",
            text: "Who affected the shape of your day?",
            category: .people,
            tags: ["people"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ022",
            text: "What conversation stayed with you?",
            category: .people,
            tags: ["people", "messages"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ023",
            text: "What did you wish someone understood today?",
            category: .people,
            tags: ["people"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ024",
            text: "What message changed your mood a little?",
            category: .people,
            tags: ["people", "messages"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ025",
            text: "What did you say yes to, and how did it feel?",
            category: .people,
            tags: ["people"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ026",
            text: "What did you not say out loud?",
            category: .people,
            tags: ["people", "avoided"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ027",
            text: "Where did you feel connected, even briefly?",
            category: .people,
            tags: ["people"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ028",
            text: "Where did you feel far away from people?",
            category: .people,
            tags: ["people"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ029",
            text: "What kindness did you receive or miss?",
            category: .people,
            tags: ["people"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ030",
            text: "What did someone do that stayed in your head?",
            category: .people,
            tags: ["people"],
            modeSuitability: .both
        )
    ]

    // MARK: - Work, pressure, and avoidance (UQ031–UQ040)

    static let work: [UniversalQuestion] = [
        UniversalQuestion(
            id: "UQ031",
            text: "What asked the most from you today?",
            category: .work,
            tags: ["work"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ032",
            text: "What did you avoid, and was it trying to protect you?",
            category: .work,
            tags: ["work", "avoided"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ033",
            text: "What task followed you after it ended?",
            category: .work,
            tags: ["work"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ034",
            text: "What felt like progress, even if it was small?",
            category: .work,
            tags: ["work", "tiny win"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ035",
            text: "What decision took more energy than expected?",
            category: .work,
            tags: ["work"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ036",
            text: "What did you finish, pause, or postpone?",
            category: .work,
            tags: ["work"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ037",
            text: "What pressure was real, and what pressure was imagined?",
            category: .work,
            tags: ["work"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ038",
            text: "What part of responsibility felt human today?",
            category: .work,
            tags: ["work"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ039",
            text: "What tiny win deserves a mark?",
            category: .work,
            tags: ["work", "tiny win"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ040",
            text: "Where did you do enough?",
            category: .work,
            tags: ["work"],
            modeSuitability: .both
        )
    ]

    // MARK: - Home, world, and tiny details (UQ041–UQ050)

    static let home: [UniversalQuestion] = [
        UniversalQuestion(
            id: "UQ041",
            text: "What did your space do to your mood today?",
            category: .home,
            tags: ["home"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ042",
            text: "What sound, light, smell, or weather changed the day?",
            category: .home,
            tags: ["home", "outside"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ043",
            text: "What outside thing pulled your attention?",
            category: .home,
            tags: ["home", "outside"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ044",
            text: "What did money make louder or quieter today?",
            category: .home,
            tags: ["home", "money"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ045",
            text: "What did your screen give you, and what did it take?",
            category: .home,
            tags: ["home", "screen"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ046",
            text: "What felt beautiful for half a second?",
            category: .home,
            tags: ["home"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ047",
            text: "What felt annoying but also ordinary?",
            category: .home,
            tags: ["home"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ048",
            text: "What did you wish the day had made room for?",
            category: .home,
            tags: ["home"],
            modeSuitability: .write
        ),
        UniversalQuestion(
            id: "UQ049",
            text: "What should future you know about this day?",
            category: .home,
            tags: ["home", "blank"],
            modeSuitability: .both
        ),
        UniversalQuestion(
            id: "UQ050",
            text: "What question do you wish someone gently asked you today?",
            category: .home,
            tags: ["blank"],
            modeSuitability: .write
        )
    ]

    // MARK: - Lookup

    static func find(id: String) -> UniversalQuestion? {
        all.first { $0.id == id }
    }

    static func matching(tags: [String]) -> [UniversalQuestion] {
        let tagSet = Set(tags)
        return all.filter { !Set($0.tags).isDisjoint(with: tagSet) }
    }
}

// MARK: - UniversalQuestion model

struct UniversalQuestion: Identifiable, Equatable {
    let id: String
    let text: String
    let category: QuestionCategory
    let tags: [String]
    let modeSuitability: ModeSuitability
    /// Always .safe for universal questions.
    let personalLevel: QuestionPersonal = .safe

    enum ModeSuitability: String {
        case write
        case talk
        case both
    }

    func isSuitable(for mode: QuestionMode) -> Bool {
        switch modeSuitability {
        case .both:  return true
        case .write: return mode == .write
        case .talk:  return mode == .talk
        }
    }

    /// Maps to a QuestionCard for display in the panel or session.
    func asCard(
        lead: String = "Start here",
        source: QuestionSource = .universal,
        accent: QuestionCard.Accent = .soft,
        rung: QuestionRung = .specificQuestion
    ) -> QuestionCard {
        QuestionCard(
            id: id,
            lead: lead,
            question: text,
            category: category,
            tags: tags,
            source: source,
            personalLevel: .safe,
            accent: accent,
            answerStyle: .open,
            rung: rung
        )
    }
}

import XCTest
@testable import Italiano

final class IrregularVerbTests: XCTestCase {
    private let withoutImperative: Set<String> = ["potere", "volere", "dovere", "piacere"]

    private func it(_ verb: String, _ tense: Tense, _ person: Int, _ gender: Gender? = nil) -> String {
        VerbLibrary.verb(verb).italian(tense, person, gender: gender)
    }

    private func de(_ verb: String, _ tense: Tense, _ person: Int) -> String {
        VerbLibrary.verb(verb).german(tense, person)
    }

    func testAllThirtyVerbsAreComplete() {
        XCTAssertEqual(VerbLibrary.irregularKeys.count, 30)
        XCTAssertEqual(VerbLibrary.irregularKeys, VerbLibrary.irregularKeys.sorted())
        for key in VerbLibrary.irregularKeys {
            let verb = VerbLibrary.verb(key)
            XCTAssertTrue(verb.isIrregular)
            for tense in Tense.allCases {
                if tense == .imperativo && withoutImperative.contains(key) {
                    XCTAssertFalse(verb.hasTense(tense), key)
                    continue
                }
                for person in tense.persons {
                    XCTAssertFalse(verb.italian(tense, person).isEmpty, "\(key) \(tense) \(person)")
                    XCTAssertFalse(verb.german(tense, person).isEmpty, "\(key) \(tense) \(person) de")
                }
            }
            XCTAssertFalse(verb.hasForm(.imperativo, 0))
        }
    }

    func testSampleForms() {
        XCTAssertEqual(it("andare", .presente, 0), "vado")
        XCTAssertEqual(it("venire", .presente, 5), "vengono")
        XCTAssertEqual(it("bere", .presente, 0), "bevo")
        XCTAssertEqual(it("essere", .imperfetto, 3), "eravamo")
        XCTAssertEqual(it("fare", .imperfetto, 0), "facevo")
        XCTAssertEqual(it("essere", .futuro, 0), "sarò")
        XCTAssertEqual(it("andare", .futuro, 0), "andrò")
        XCTAssertEqual(it("rimanere", .futuro, 3), "rimarremo")
        XCTAssertEqual(it("volere", .condizionale, 0), "vorrei")
        XCTAssertEqual(it("dovere", .condizionale, 2), "dovrebbe")
        XCTAssertEqual(it("bere", .condizionale, 5), "berrebbero")
        XCTAssertEqual(it("essere", .congiuntivo, 0), "sia")
        XCTAssertEqual(it("andare", .congiuntivo, 5), "vadano")
        XCTAssertEqual(it("sapere", .congiuntivo, 4), "sappiate")
        XCTAssertEqual(it("essere", .imperativo, 1), "sii")
        XCTAssertEqual(it("avere", .imperativo, 4), "abbiate")
        XCTAssertEqual(it("dire", .imperativo, 1), "di'")
        XCTAssertEqual(it("essere", .passatoprossimo, 0, .feminine), "sono stata")
        XCTAssertEqual(it("fare", .passatoprossimo, 0, .feminine), "ho fatto")
        XCTAssertEqual(it("piacere", .passatoprossimo, 2), "è piaciuto")
        XCTAssertEqual(it("rimanere", .passatoprossimo, 5), "sono rimasti")
    }

    func testGermanForms() {
        XCTAssertEqual(de("stare", .presente, 0), "befinde mich")
        XCTAssertEqual(de("stare", .condizionale, 1), "würdest dich befinden")
        XCTAssertEqual(de("stare", .passatoprossimo, 3), "haben uns befunden")
        XCTAssertEqual(de("piacere", .passatoprossimo, 2), "hat gefallen")
        XCTAssertEqual(de("cadere", .passatoprossimo, 2), "ist gefallen")
        XCTAssertEqual(de("fare", .futuro, 0), "werde machen")
        XCTAssertEqual(de("essere", .imperativo, 2), "seien sie")
        XCTAssertEqual(de("uscire", .imperativo, 4), "geht aus")
        XCTAssertEqual(de("prendere", .imperativo, 1), "nimm")
    }

    func testImperativeAlternativesAreAccepted() throws {
        let defaults = UserDefaults(suiteName: "IrregularVerbTests")!
        defaults.removePersistentDomain(forName: "IrregularVerbTests")
        seedPool([("fare", .presente), ("fare", .imperativo)], in: defaults)
        let store = makeStore(defaults)
        store.conjugation.mode = .free
        store.conjugation.verbs = ["fare"]
        store.conjugation.tenses = [.imperativo]
        store.conjugation.length = .count(5)
        let lesson = ConjugationLesson(store: store)
        while let item = lesson.current, item.person != 1 {
            lesson.reveal(); lesson.submit("")
        }
        let item = try XCTUnwrap(lesson.current)
        XCTAssertEqual(item.answer, "fa'")
        lesson.submit("fai")
        XCTAssertEqual(lesson.feedback, .correct("fa'"))
        XCTAssertEqual(normalize("Fa’"), "fa'")
    }

    func testVerbsWithoutImperativeAreSkipped() {
        let pool = ConjugationLesson.pool(verbs: ["potere", "andare"], tenses: [.imperativo])
        XCTAssertEqual(pool.count, 5)
        XCTAssertTrue(pool.allSatisfy { $0.verb == "andare" })

        let defaults = UserDefaults(suiteName: "IrregularVerbTests2")!
        defaults.removePersistentDomain(forName: "IrregularVerbTests2")
        seedPool([("potere", .presente)], in: defaults)
        let store = makeStore(defaults)
        store.practise("potere", .presente, answers: 20)
        XCTAssertGreaterThan(store.level(of: "potere", tense: .presente), 0)
        // potere has no imperative, so it does not pull the average down.
        XCTAssertEqual(store.level(of: "potere", tenses: [.presente, .imperativo]),
                       store.level(of: "potere", tense: .presente))
    }

    func testTableFormsShowGendersAndVariants() {
        XCTAssertEqual(VerbLibrary.verb("andare").tableForm(.passatoprossimo, 0), "sono andato/a")
        XCTAssertEqual(VerbLibrary.verb("andare").tableForm(.passatoprossimo, 3), "siamo andati/e")
        XCTAssertEqual(VerbLibrary.verb("andare").tableForm(.imperativo, 1), "va' / vai")
        XCTAssertEqual(VerbLibrary.verb("fare").tableForm(.passatoprossimo, 0), "ho fatto")
        XCTAssertEqual(VerbLibrary.verb("dire").tableForm(.imperativo, 1), "di'")
        XCTAssertNil(VerbLibrary.verb("dire").tableForm(.imperativo, 0))
        XCTAssertNil(VerbLibrary.verb("potere").tableForm(.imperativo, 1))
        XCTAssertEqual(VerbLibrary.verb("parlare").tableForm(.presente, 0), "parlo")
    }

    func testIrregularVerbsHaveTheirOwnGroup() {
        XCTAssertEqual(VerbLibrary.groups.last?.label, "Unregelmäßig")
        XCTAssertEqual(VerbLibrary.groups.last?.verbs.count, 30)
        XCTAssertNil(VerbLibrary.verb("dare").spellingNote)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("irr-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let history = AnswerHistory(fileURL: url)
        history.record(verb: "fare", tense: .presente, correct: false)
        history.record(verb: "parlare", tense: .presente, correct: true)
        let window = history.window(for: .days3)
        XCTAssertEqual(history.byGroup(in: window, tense: .presente).map(\.label), ["-are", "Unregelmäßig"])
        XCTAssertTrue(history.byGroup(in: window, tense: .passatoprossimo).isEmpty)
    }

    func testSavedSettingsDoNotSwitchOnIrregularVerbs() {
        let defaults = UserDefaults(suiteName: "IrregularVerbTests3")!
        defaults.removePersistentDomain(forName: "IrregularVerbTests3")
        let regular = Set(VerbCatalog.seeds.map(\.infinitive))
        seedPool(regular.map { ($0, .presente) }, in: defaults)
        let first = makeStore(defaults)
        first.conjugation.verbs = regular
        XCTAssertEqual(makeStore(defaults).conjugation.verbs, regular)
    }
}

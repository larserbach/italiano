import XCTest
@testable import Italiano

/// Every form the app derives must match the reference forms in the fixture.
final class VerbFormsTests: XCTestCase {
    private typealias Fixture = [String: [String: [String: [String?]]]]

    func testAllFormsMatchFixture() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "verb-forms", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))

        XCTAssertEqual(Set(fixture.keys), Set(VerbCatalog.seeds.map(\.infinitive)))
        for (key, languages) in fixture {
            let verb = VerbLibrary.verb(key)
            for tense in Tense.allCases {
                XCTAssertEqual(verb.italian[tense], languages["it"]?[tense.rawValue], "\(key) \(tense) it")
                XCTAssertEqual(verb.german[tense], languages["de"]?[tense.rawValue], "\(key) \(tense) de")
            }
        }
    }

    func testImperativeHasNoIoForm() {
        let pool = ConjugationLesson.pool(verbs: ["parlare"], tenses: [.imperativo, .presente])
        XCTAssertEqual(pool.count, 11)
        XCTAssertFalse(pool.contains { $0.tense == .imperativo && $0.person == 0 })
    }

    func testSpellingNotesCoverSpecialVerbs() {
        XCTAssertEqual(VerbLibrary.verb("viaggiare").spellingNote,
                       "Das i macht nur das g weich. Vor i und e fällt es weg: tu viaggi, noi viaggiamo, viaggerò, che loro viaggino.")
        XCTAssertTrue(VerbLibrary.verb("sciare").spellingNote?.contains("tu scii, scierò, che loro sciino") == true)
        XCTAssertTrue(VerbLibrary.verb("mancare").spellingNote?.contains("tu manchi, mancherò") == true)
        XCTAssertNil(VerbLibrary.verb("parlare").spellingNote)
        let withNotes = VerbLibrary.orderedKeys.filter { VerbLibrary.verb($0).spellingNote != nil }
        XCTAssertEqual(Set(withNotes), ["viaggiare", "passeggiare", "sciare", "mancare"])
    }

    func testEssereParticipleAgreesWithGender() {
        let arrivare = VerbLibrary.verb("arrivare")
        XCTAssertEqual((0..<6).map { arrivare.italian(.passatoprossimo, $0, gender: .feminine) },
                       ["sono arrivata", "sei arrivata", "è arrivata", "siamo arrivate", "siete arrivate", "sono arrivate"])
        XCTAssertEqual(arrivare.italian(.passatoprossimo, 3, gender: .masculine), "siamo arrivati")
        XCTAssertEqual(VerbLibrary.verb("parlare").italian(.passatoprossimo, 2, gender: .feminine), "ha parlato")
        XCTAssertEqual(arrivare.italian(.presente, 0, gender: .feminine), "arrivo")

        let gendered = VerbCatalog.seeds.map(\.infinitive).filter { VerbLibrary.verb($0).isGendered(.passatoprossimo) }
        XCTAssertEqual(Set(gendered), ["arrivare", "diventare", "durare", "entrare", "mancare", "restare",
                                       "sembrare", "tornare", "bastare", "partire", "scendere", "fuggire"])
        XCTAssertFalse(Tense.allCases.filter { $0 != .passatoprossimo }.contains { arrivare.isGendered($0) })
    }

    func testPronounShowsGender() {
        XCTAssertEqual(Pronoun.italian(2, gender: .feminine), "lei")
        XCTAssertEqual(Pronoun.german(2, gender: .masculine), "er")
        XCTAssertEqual(Pronoun.italian(2, gender: nil), "lui/lei")
    }

    func testNormalizeIgnoresCaseAndSpacing() {
        XCTAssertEqual(normalize("  Ho   PARLATO "), "ho parlato")
    }
}

import XCTest
@testable import Italiano

final class FamilyInfoTests: XCTestCase {
    private func section(_ heading: String, of family: VerbFamily) -> TenseInfo.Content? {
        FamilyInfo.of(family).sections.first { $0.heading == heading }?.content
    }

    func testEveryGroupHasTextsAndAPlainModelVerb() {
        XCTAssertEqual(VerbFamily.regular.map { FamilyInfo.of($0).examples.first }, ["parlare", "credere", "dormire", "capire"])
        for family in VerbFamily.regular {
            let info = FamilyInfo.of(family)
            XCTAssertFalse(info.formation.isEmpty, family.label)
            XCTAssertTrue(info.examples.allSatisfy { VerbLibrary.verb($0).irregularTenses.isEmpty }, family.label)
            XCTAssertEqual(info.examples, Curriculum.verbOrder.filter(info.examples.contains), "path order")
        }
    }

    func testExamplesIncludeTheVerbsTheCaveatsAreAbout() {
        let examples = FamilyInfo.of(.are).examples
        XCTAssertEqual(examples.count, FamilyInfo.maxExamples)
        for verb in ["viaggiare", "passeggiare", "mancare", "sciare", "arrivare"] {
            XCTAssertTrue(examples.contains(verb), verb)
        }
    }

    func testEndingsAreSetApartFromTheStem() {
        XCTAssertTrue(FamilyInfo.split("parlo", infinitive: "parlare") == ("parl", "o"))
        XCTAssertTrue(FamilyInfo.split("ho parlato", infinitive: "parlare") == ("ho parl", "ato"))
        XCTAssertTrue(FamilyInfo.split("sono arrivato/a", infinitive: "arrivare") == ("sono arriv", "ato/a"))
        XCTAssertTrue(FamilyInfo.split("capisco", infinitive: "capire") == ("cap", "isco"))
        XCTAssertTrue(FamilyInfo.split("mancherò", infinitive: "mancare") == ("manc", "herò"))
        XCTAssertTrue(FamilyInfo.split("viaggerò", infinitive: "viaggiare") == ("viagg", "erò"))
    }

    func testCaveatsListTheGroupsVerbsFromTheCatalog() throws {
        guard case .list(let notes) = section("Schreibung beachten", of: .are) else { return XCTFail("no spelling notes") }
        XCTAssertEqual(notes.map(\.label), ["viaggiare:", "mancare:", "passeggiare:", "sciare:"])

        guard case .paragraph(let essere) = section("Passato prossimo mit essere", of: .are) else { return XCTFail("no essere") }
        XCTAssertTrue(essere.hasPrefix("andare, stare, arrivare"))
        XCTAssertTrue(essere.contains("sono andato/a"))

        guard case .table(_, let participles) = section("Eigenes Partizip", of: .ere) else { return XCTFail("no participles") }
        XCTAssertTrue(participles.contains(["scrivere", "scritto"]))
        XCTAssertNil(section("Eigenes Partizip", of: .are))

        guard case .table(_, let tenses) = section("Eigene Formen in einzelnen Zeiten", of: .are) else { return XCTFail("no own tenses") }
        XCTAssertEqual(tenses.map(\.[0]), ["andare", "stare", "dare"])
    }

    func testIscVerbsAreRegularThroughoutAndTakeAvere() {
        let info = FamilyInfo.of(.isc)
        XCTAssertEqual(info.summary, "12 Verben, alle in jeder Zeit regelmäßig")
        XCTAssertFalse(info.formation.contains { $0.label == "Ausnahmen:" })
        XCTAssertEqual(info.sections.map(\.heading), ["Beachten", "Passato prossimo mit avere"])
    }
}

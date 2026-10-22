import XCTest
@testable import Italiano

final class MigrationTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "MigrationTests")
        defaults.removePersistentDomain(forName: "MigrationTests")
    }

    func testEarlierCellsBecomeGroupsAndIrregularVerbs() throws {
        defaults.set(try JSONSerialization.data(withJSONObject: [
            "cells": [["verb": "parlare", "tense": "presente"], ["verb": "abitare", "tense": "presente"],
                      ["verb": "capire", "tense": "passatoprossimo"], ["verb": "fare", "tense": "presente"]],
        ]), forKey: "coniugazione-pool")
        defaults.set(Data("{}".utf8), forKey: "coniugazione-dsr-memory")
        let store = makeStore(defaults)
        XCTAssertEqual(store.pool.units, [.group(.are, .presente), .irregular("essere", .presente),
                                          .group(.isc, .passatoprossimo), .irregular("fare", .presente)])
        XCTAssertNil(defaults.data(forKey: "coniugazione-pool"))
        XCTAssertNil(defaults.data(forKey: "coniugazione-dsr-memory"))
        XCTAssertEqual(makeStore(defaults).pool.units, store.pool.units)
    }

    func testTheFirstLearningPathCarriesOverToo() throws {
        defaults.set(try JSONSerialization.data(withJSONObject: [
            "unlocked": [["verb": "parlare", "tense": "presente"], ["verb": "credere", "tense": "presente"]],
            "frontier": "credere",
        ]), forKey: "coniugazione-curriculum")
        XCTAssertEqual(makeStore(defaults).pool.units, [.group(.are, .presente), .irregular("essere", .presente),
                                                        .group(.ere, .presente)])
    }

    func testOlderProgressKeysAreRemoved() throws {
        defaults.set(try JSONEncoder().encode(["parlare": 7]), forKey: "coniugazione-levels")
        defaults.set(try JSONEncoder().encode(["parlare": ["presente": 3]]), forKey: "coniugazione-tense-levels")
        // The red marks of free practice.
        defaults.set(try JSONEncoder().encode(["parlare|presente"]), forKey: "coniugazione-tense-mistakes")
        let store = makeStore(defaults)
        XCTAssertEqual(store.pool.units, LearningPool.startUnits)
        XCTAssertNil(defaults.data(forKey: "coniugazione-levels"))
        XCTAssertNil(defaults.data(forKey: "coniugazione-tense-levels"))
        XCTAssertNil(defaults.data(forKey: "coniugazione-tense-mistakes"))
    }
}

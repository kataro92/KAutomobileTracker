import Foundation
import KAutomobileTrackerCore
import XCTest

final class DashcamHTMLParserTests: XCTestCase {
    func testParsesVideoPathsFromCGIStyleBody() {
        let body = #"<?xml st=0><file>/NORMAL/2024_0101_120000.MOV</file>"#
        let paths = DashcamHTMLParser.videoPaths(in: body)
        XCTAssertTrue(paths.contains("/NORMAL/2024_0101_120000.MOV"))
    }

    func testParsesHrefsFromSimpleHtml() {
        let base = URL(string: "http://192.168.1.254/")!
        let html = #"<html><a href="SUB/clip.MOV">x</a></html>"#
        let paths = DashcamHTMLParser.videoHrefs(in: html, baseURL: base)
        XCTAssertTrue(paths.contains("/SUB/clip.MOV"))
    }

    func testTripsDocumentRoundTrip() throws {
        let trip = TripRecord(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isTracked: true,
            inputKind: .wifiNiceDVR,
            sourceLabel: "test"
        )
        let doc = TripsDocument(schemaVersion: TripsSchema.currentVersion, trips: [trip])
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(TripsDocument.self, from: data)
        XCTAssertEqual(decoded.trips.count, 1)
        XCTAssertEqual(decoded.schemaVersion, TripsSchema.currentVersion)
    }
}

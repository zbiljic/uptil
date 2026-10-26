import AppKit
import Foundation
import Testing
@testable import UpTil

@MainActor
@Suite("About presentation")
struct AboutPresentationTests {
    @Test("about menu names its icon, links, and version")
    func aboutPresentationIsStable() {
        #expect(AboutPresentation.systemImage == "info.circle")
        #expect(AboutPresentation.Link.allCases == [.projectPage, .reportIssue])
        #expect(AboutPresentation.Link.allCases.map(\.title) == ["Project Page", "Report an Issue…"])
        #expect(AboutPresentation.Link.projectPage.url?.absoluteString == "https://github.com/zbiljic/uptil")
        #expect(AboutPresentation.Link.reportIssue.url?.absoluteString == "https://github.com/zbiljic/uptil/issues")
        #expect(AboutPresentation.versionLabel(version: "0.2.0") == "UpTil 0.2.0")
        #expect(AboutPresentation.versionLabel(version: nil) == "UpTil dev")
    }

    @Test("about links open their pages", arguments: AboutPresentation.Link.allCases)
    func aboutLinksOpenTheirPages(link: AboutPresentation.Link) throws {
        var opened: [URL] = []

        let didOpen = AboutPresentation.open(link) { url in
            opened.append(url)
            return true
        }

        #expect(didOpen)
        #expect(try opened == [#require(link.url)])
    }

    @Test("about menu lists the version, then one item per link")
    func aboutMenuListsVersionThenLinks() {
        let target = NSObject()

        let menu = AboutPresentation.menu(target: target, action: #selector(NSObject.description))

        #expect(menu.items.map(\.title) == [AboutPresentation.versionLabel(), "", "Project Page", "Report an Issue…"])
        #expect(menu.items.map(\.isEnabled) == [false, false, true, true])
        #expect(menu.items[1].isSeparatorItem)
        #expect(menu.items.dropFirst(2).map { $0.representedObject as? AboutPresentation.Link } == [
            .projectPage,
            .reportIssue,
        ])
        #expect(menu.items.dropFirst(2).allSatisfy { $0.target === target })
    }

    @Test("built app reports the marketing version from its bundle")
    func builtAppReportsMarketingVersion() throws {
        let version = try #require(AppMetadata.version())

        #expect(version.split(separator: ".").count == 3)
        #expect(AboutPresentation.versionLabel() == "UpTil \(version)")
    }
}

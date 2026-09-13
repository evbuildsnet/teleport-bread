import Foundation
import Testing
@testable import InboxCore

@Suite struct VersionRequirementTests {
    @Test(arguments: [
        ("1.9", "1.10"), ("1.0.9", "1.0.10"), ("1", "1.0.1"),
        ("1.99", "2"), ("0.9", "1.0"),
    ])
    func comparesNumericComponents(versions: (String, String)) throws {
        let older = try #require(AppVersion(versions.0))
        let newer = try #require(AppVersion(versions.1))
        #expect(older < newer)
        #expect(!(newer < older))
    }

    @Test(arguments: ["1", "1.0", "1.0.0", "01.00"])
    func trailingZerosAreEqual(version: String) {
        #expect(AppVersion(version) == AppVersion("1.0"))
    }

    @Test(arguments: ["", "1..0", "1.", ".1", "-1", "1.beta", " 1.0", "1.0\n", "999999999999999999999999"])
    func rejectsMalformedVersions(version: String) {
        #expect(AppVersion(version) == nil)
        #expect(VersionRequirement(data: policy, platform: .ios, currentVersion: version) == nil)
    }

    private let policy = Data(#"{"ios":{"minimum":"1.1","latest":"1.10"},"mac":{"minimum":"2.0","latest":"2.1"}}"#.utf8)

    @Test func selectsPlatformAndDistinguishesRequiredFromAvailable() throws {
        let required = try #require(VersionRequirement(data: policy, platform: .mac, currentVersion: "1.9"))
        #expect(required.required)
        #expect(required.available)
        #expect(required.minimum == "2.0")
        let soft = try #require(VersionRequirement(data: policy, platform: .ios, currentVersion: "1.9"))
        #expect(!soft.required)
        #expect(soft.available)
        let atMinimum = try #require(VersionRequirement(data: policy, platform: .ios, currentVersion: "1.1.0"))
        #expect(!atMinimum.required)
        for version in ["1.10", "1.10.0", "2.0"] {
            let current = try #require(VersionRequirement(data: policy, platform: .ios, currentVersion: version))
            #expect(!current.required)
            #expect(!current.available)
        }
    }

    @Test(arguments: [
        "not JSON", "{}", #"{"mac":{"minimum":"2","latest":"3"}}"#,
        #"{"ios":{"latest":"3"}}"#, #"{"ios":{"minimum":"2"}}"#,
        #"{"ios":{"minimum":2,"latest":"3"}}"#,
        #"{"ios":{"minimum":"oops","latest":"3"}}"#,
        #"{"ios":{"minimum":"2","latest":"oops"}}"#,
        #"{"ios":{"minimum":"3","latest":"2"}}"#,
    ])
    func unusablePolicyFailsOpen(json: String) {
        #expect(VersionRequirement(data: Data(json.utf8), platform: .ios, currentVersion: "1") == nil)
    }

    @Test func routesStoreAndTestFlightAndPreservesMessage() throws {
        let data = Data(#"{"ios":{"minimum":"2","latest":"3","store":"https://apps.apple.com/app/id12345","testflight":"https://testflight.apple.com/join/EjA9WTnY","message":"  A reminder safety fix.  "}}"#.utf8)
        let requirement = try #require(VersionRequirement(data: data, platform: .ios, currentVersion: "1"))
        #expect(requirement.message == "A reminder safety fix.")
        #expect(requirement.updateURL(isTestFlight: false)?.absoluteString == "https://apps.apple.com/app/id12345")
        #expect(requirement.updateURL(isTestFlight: true)?.absoluteString == "https://testflight.apple.com/join/EjA9WTnY")
    }

    @Test(arguments: [
        "",
        #", "store":"not a URL", "testflight":"bad""#,
        #", "store":"file:///tmp/update""#,
    ])
    func unpublishedURLsFallBackAndBlankMessageUsesDefault(fields: String) throws {
        let data = Data("{\"ios\":{\"minimum\":\"2\",\"latest\":\"3\",\"message\":\"  \"\(fields)}}".utf8)
        let requirement = try #require(VersionRequirement(data: data, platform: .ios, currentVersion: "1"))
        #expect(requirement.message == nil)
        for isTestFlight in [false, true] {
            #expect(requirement.updateURL(isTestFlight: isTestFlight)?.absoluteString == "https://teleportbread.com")
        }
    }
}

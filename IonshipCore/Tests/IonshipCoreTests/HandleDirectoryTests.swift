import Testing
@testable import IonshipCore

@Suite struct HandleDirectoryTests {
    let directory = HandleDirectory(entries: [
        .init(name: "Mom", phones: ["+1 (555) 010-4471"], emails: ["Mom@Example.com"]),
        .init(name: "Maya Chen", phones: [], emails: ["maya@example.com"]),
        .init(name: "Pizza Place", phones: ["72345"], emails: []),
    ])

    @Test(arguments: ["+15550104471", "5550104471", "15550104471", "+1 555 010 4471"])
    func phoneFormatsMatch(_ handle: String) {
        #expect(directory.name(for: handle) == "Mom")
    }

    @Test func emailsMatchCaseInsensitively() {
        #expect(directory.name(for: "mom@example.com") == "Mom")
        #expect(directory.name(for: "MAYA@example.com") == "Maya Chen")
    }

    @Test func shortCodesMatchExactly() {
        #expect(directory.name(for: "72345") == "Pizza Place")
        #expect(directory.name(for: "172345") == nil)
    }

    @Test func unknownHandlesAreNil() {
        #expect(directory.name(for: "+15559999999") == nil)
        #expect(directory.name(for: "stranger@example.com") == nil)
        #expect(directory.name(for: "") == nil)
    }

    @Test func firstContactWinsOnDuplicateHandles() {
        let directory = HandleDirectory(entries: [
            .init(name: "Work Phone", phones: ["5550104471"], emails: []),
            .init(name: "Mom", phones: ["+15550104471"], emails: []),
        ])
        #expect(directory.name(for: "+15550104471") == "Work Phone")
    }

    @Test func phoneAndEmailOfOneContactShareAKey() {
        #expect(directory.contactKey(for: "+15550104471") != nil)
        #expect(directory.contactKey(for: "+15550104471") == directory.contactKey(for: "mom@example.com"))
        #expect(directory.contactKey(for: "maya@example.com") != directory.contactKey(for: "mom@example.com"))
        #expect(directory.contactKey(for: "+15559999999") == nil)
    }
}

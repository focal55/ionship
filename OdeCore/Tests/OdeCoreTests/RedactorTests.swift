import Foundation
import Testing
@testable import OdeCore

@Suite struct RedactorTests {
    @Test func emailsAndPhonesBecomeNumberedPlaceholders() {
        var redactor = Redactor()
        let out = redactor.redact("email maya@example.com or call (555) 010-4471, or maya@example.com again")
        #expect(out == "email [EMAIL 1] or call [PHONE 1], or [EMAIL 1] again")
    }

    @Test func placeholdersAreRestoredInReplies() {
        var redactor = Redactor()
        _ = redactor.redact("my new number is +1 555 010 4471")
        #expect(redactor.restore("got it, saving [PHONE 1] now") == "got it, saving +1 555 010 4471 now")
    }

    @Test func streetAddressesAreRedacted() {
        var redactor = Redactor()
        let out = redactor.redact("meet at 1 Infinite Loop, Cupertino, CA 95014 at noon")
        #expect(!out.contains("Infinite Loop"))
        #expect(out.contains("[ADDRESS 1]"))
    }

    @Test func numberingIsSharedAcrossCallsForOneConversation() {
        var redactor = Redactor()
        #expect(redactor.redact("a@b.com") == "[EMAIL 1]")
        #expect(redactor.redact("c@d.com and a@b.com") == "[EMAIL 2] and [EMAIL 1]")
    }

    @Test func plainTextIsUntouched() {
        var redactor = Redactor()
        #expect(redactor.redact("see you at 7, bring 2 bottles") == "see you at 7, bring 2 bottles")
    }
}

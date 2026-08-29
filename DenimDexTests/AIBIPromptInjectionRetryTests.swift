import XCTest
@testable import DenimDex

final class AIBIPromptInjectionRetryTests: XCTestCase {
    func testSuccessfulInjectionVerifiedAgainstComposerIsInjected() {
        let outcome = AIBISession.classifyInjectionAttempt(
            injectSucceeded: true,
            injectCode: nil,
            verifiedMatch: true
        )
        XCTAssertEqual(outcome, .injected)
    }

    func testMissingInputIsRetryableNotTerminal() {
        let outcome = AIBISession.classifyInjectionAttempt(
            injectSucceeded: false,
            injectCode: "INPUT_NOT_FOUND",
            verifiedMatch: false
        )
        XCTAssertEqual(outcome, .retryable)
    }

    func testSuccessWithoutVerifiedTextIsRetryable() {
        // ChatGPT can report success but swap the composer node before the follow-up
        // verification call lands, so the text never actually persisted.
        let outcome = AIBISession.classifyInjectionAttempt(
            injectSucceeded: true,
            injectCode: nil,
            verifiedMatch: false
        )
        XCTAssertEqual(outcome, .retryable)
    }

    func testExistingDifferentTextIsTerminalRegardlessOfVerification() {
        let outcome = AIBISession.classifyInjectionAttempt(
            injectSucceeded: false,
            injectCode: "EXISTING_TEXT_PRESERVED",
            verifiedMatch: false
        )
        XCTAssertEqual(outcome, .terminal)

        let outcomeEvenIfSomehowVerified = AIBISession.classifyInjectionAttempt(
            injectSucceeded: false,
            injectCode: "EXISTING_TEXT_PRESERVED",
            verifiedMatch: true
        )
        XCTAssertEqual(outcomeEvenIfSomehowVerified, .terminal)
    }
}

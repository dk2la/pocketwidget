import XCTest

/// Mail setup fills the password by itself when the copied text has the
/// shape of the chosen provider's app password — and only then.
final class MailAppPasswordTests: XCTestCase {
    // MARK: - Gmail: 16 lowercase letters, shown as four groups of four

    func testGmailTakesFourGroupsSeparatedBySpaces() {
        XCTAssertEqual(EmailProvider.gmail.appPassword(in: "abcd efgh ijkl mnop"), "abcdefghijklmnop")
    }

    func testGmailTakesGroupsSeparatedByNonBreakingSpaces() {
        XCTAssertEqual(
            EmailProvider.gmail.appPassword(in: "abcd\u{00A0}efgh\u{00A0}ijkl\u{00A0}mnop"),
            "abcdefghijklmnop"
        )
    }

    func testGmailTakesSixteenLettersInOnePiece() {
        XCTAssertEqual(EmailProvider.gmail.appPassword(in: "abcdefghijklmnop"), "abcdefghijklmnop")
    }

    func testGmailIgnoresSurroundingWhitespace() {
        XCTAssertEqual(EmailProvider.gmail.appPassword(in: "  abcd efgh ijkl mnop\n"), "abcdefghijklmnop")
    }

    func testGmailIgnoresOtherText() {
        let provider = EmailProvider.gmail
        XCTAssertNil(provider.appPassword(in: ""))
        XCTAssertNil(provider.appPassword(in: "hello world"))
        XCTAssertNil(provider.appPassword(in: "abcd efgh ijkl mno"))
        XCTAssertNil(provider.appPassword(in: "abcd efgh ijkl mnopq"))
        XCTAssertNil(provider.appPassword(in: "Abcd efgh ijkl mnop"))
        XCTAssertNil(provider.appPassword(in: "abc1 efgh ijkl mnop"))
        XCTAssertNil(provider.appPassword(in: "abcd-efgh-ijkl-mnop"))
        XCTAssertNil(provider.appPassword(in: "abcde fgh ijkl mnop"))
        XCTAssertNil(provider.appPassword(in: "password: abcd efgh ijkl mnop"))
        XCTAssertNil(provider.appPassword(in: "abcd efgh\nijkl mnop"))
    }

    // MARK: - iCloud: xxxx-xxxx-xxxx-xxxx

    func testICloudTakesFourGroupsSeparatedByHyphens() {
        XCTAssertEqual(EmailProvider.icloud.appPassword(in: "abcd-efgh-ijkl-mnop"), "abcd-efgh-ijkl-mnop")
        XCTAssertEqual(EmailProvider.icloud.appPassword(in: " abcd-efgh-ijkl-mnop\n"), "abcd-efgh-ijkl-mnop")
    }

    func testICloudIgnoresOtherText() {
        let provider = EmailProvider.icloud
        XCTAssertNil(provider.appPassword(in: "abcdefghijklmnop"))
        XCTAssertNil(provider.appPassword(in: "abcd efgh ijkl mnop"))
        XCTAssertNil(provider.appPassword(in: "abcd-efgh-ijkl"))
        XCTAssertNil(provider.appPassword(in: "abcd-efgh-ijkl-mnop-qrst"))
        XCTAssertNil(provider.appPassword(in: "ABCD-EFGH-IJKL-MNOP"))
        XCTAssertNil(provider.appPassword(in: "abcd-efgh-ijkl-mn0p"))
        XCTAssertNil(provider.appPassword(in: "https://abcd-efgh-ijkl-mnop"))
    }

    // MARK: - Yandex: 16 lowercase letters

    func testYandexTakesSixteenLetters() {
        XCTAssertEqual(EmailProvider.yandex.appPassword(in: "abcdefghijklmnop"), "abcdefghijklmnop")
        XCTAssertEqual(EmailProvider.yandex.appPassword(in: "abcdefghijklmnop\n"), "abcdefghijklmnop")
    }

    func testYandexIgnoresOtherText() {
        let provider = EmailProvider.yandex
        XCTAssertNil(provider.appPassword(in: "abcdefghijklmno"))
        XCTAssertNil(provider.appPassword(in: "abcdefghijklmnopq"))
        XCTAssertNil(provider.appPassword(in: "abcd efgh ijkl mnop"))
        XCTAssertNil(provider.appPassword(in: "abcd-efgh-ijkl-mnop"))
        XCTAssertNil(provider.appPassword(in: "abcdefghijklmn0p"))
        XCTAssertNil(provider.appPassword(in: "Abcdefghijklmnop"))
    }

    // MARK: - Providers without an app-password page

    func testOutlookAndCustomNeverTakeCopiedText() {
        for provider in [EmailProvider.outlook, .custom] {
            XCTAssertNil(provider.appPassword(in: "abcdefghijklmnop"))
            XCTAssertNil(provider.appPassword(in: "abcd-efgh-ijkl-mnop"))
            XCTAssertNil(provider.appPasswordURL)
        }
    }

    func testProvidersWithAnAppPasswordPageEachHaveTheirOwn() {
        let pages = [EmailProvider.gmail, .icloud, .yandex].compactMap(\.appPasswordURL)
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(Set(pages).count, 3)
        XCTAssertTrue(pages.allSatisfy { $0.scheme == "https" })
    }
}

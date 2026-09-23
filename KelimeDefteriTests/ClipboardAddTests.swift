import Testing
@testable import KelimeDefteri

/// "Panodaki Kelimeyi Ekle" kısayolunun taslağı ve isteği.
struct ClipboardAddTests {
    @Test func clipboardWordBecomesTheWord() {
        let draft = ClipboardAdd.draft(text: nil) { "  Idempotent\n" }
        #expect(draft.english == "idempotent")
        #expect(draft.example.isEmpty)
    }

    @Test func givenTextWinsOverClipboard() {
        var clipboardRead = false
        let draft = ClipboardAdd.draft(text: "stale") {
            clipboardRead = true
            return "quorum"
        }
        #expect(draft.english == "stale")
        #expect(!clipboardRead)
    }

    @Test func blankTextFallsBackToClipboard() {
        let draft = ClipboardAdd.draft(text: "  ") { "A follower replica may return stale data." }
        #expect(draft.english.isEmpty)
        #expect(draft.example == "A follower replica may return stale data.")
    }

    @Test func linkOrEmptyClipboardGivesEmptyDraft() {
        #expect(ClipboardAdd.draft(text: nil) { "https://example.com/page" } == .init())
        #expect(ClipboardAdd.draft(text: nil) { nil } == .init())
    }

    @Test func eachRequestIsNewAndCounted() {
        let router = AddRouter()
        router.open(text: nil)
        let first = router.pending
        router.open(text: nil)
        #expect(router.requestCount == 2)
        #expect(router.pending != first)
        #expect(router.pending?.text == nil)
    }
}

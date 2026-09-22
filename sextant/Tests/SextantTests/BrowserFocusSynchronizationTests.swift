import Testing

@testable import Sextant

@Suite
struct BrowserFocusSynchronizationTests {
  private let browser = BrowserFocus.browser(DirectoryID(identity: .path("/fixture")))

  @Test("a transient replacement fallback cannot revoke a pending preview request")
  func replacementFallback() {
    var synchronization = BrowserFocusSynchronization()
    synchronization.request(.preview, current: browser)

    // This is the failing real-PTY sequence: the model requests preview,
    // then the retiring member publishes browser before the new member binds.
    #expect(synchronization.observe(browser, current: browser) == .request(.preview))
    #expect(synchronization.pending == .preview)
    #expect(synchronization.observe(.preview, current: .preview) == .publish(.preview))
    #expect(synchronization.pending == nil)

    // Once acknowledged, genuine runtime focus changes (including mouse
    // focus) still reach the model rather than being pinned to preview.
    #expect(synchronization.observe(browser, current: browser) == .publish(browser))
  }

  @Test("an obsolete callback cannot acknowledge or revoke a newer request")
  func obsoleteCallback() {
    var synchronization = BrowserFocusSynchronization()
    synchronization.request(.preview, current: browser)
    #expect(synchronization.observe(browser, current: .preview) == .ignore)
    #expect(synchronization.pending == .preview)
    synchronization.request(browser, current: .preview)
    #expect(synchronization.observe(.preview, current: browser) == .ignore)
    #expect(synchronization.pending == browser)
    #expect(synchronization.observe(browser, current: browser) == .publish(browser))
    #expect(synchronization.pending == nil)
  }

  @Test("a new preview member must acknowledge focus even when the old member was focused")
  func newMember() {
    var synchronization = BrowserFocusSynchronization()
    synchronization.request(.preview, current: nil)
    #expect(synchronization.observe(nil, current: nil) == .request(.preview))
    #expect(synchronization.observe(browser, current: browser) == .request(.preview))
    #expect(synchronization.observe(.preview, current: .preview) == .publish(.preview))
  }

  @Test("an already fulfilled model request does not suppress the next runtime focus change")
  func alreadyFulfilled() {
    var synchronization = BrowserFocusSynchronization()
    synchronization.request(browser, current: browser)
    #expect(synchronization.pending == nil)
    #expect(synchronization.observe(.preview, current: .preview) == .publish(.preview))
  }
}

import Foundation
import Testing

@testable import Brim

struct NotificationInboxTests {
  private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

  private func message(_ sender: String, _ body: String, app: String = "Messages",
                       bundle: String? = NotificationApps.messages, at offset: TimeInterval = 0) -> NotificationContent {
    NotificationContent(bundleID: bundle, appName: app, title: sender, body: body, date: start + offset)
  }

  @Test func firstMessageStartsAConversationWithOneUnread() {
    let inbox = NotificationInbox().recording(message("Mia Chen", "Dinner at 8?"))
    #expect(inbox.conversations.count == 1)
    #expect(inbox.conversations[0].sender == "Mia Chen")
    #expect(inbox.conversations[0].unread == 1)
    #expect(inbox.unreadTotal == 1)
  }

  @Test func sameSenderGroupsAndMovesToTop() {
    let inbox = NotificationInbox()
      .recording(message("Sam Rivera", "Look", at: 0))
      .recording(message("Mia Chen", "Dinner?", at: 1))
      .recording(message("Sam Rivera", "Look at the notch", at: 2))
    #expect(inbox.conversations.map(\.sender) == ["Sam Rivera", "Mia Chen"])
    #expect(inbox.conversations[0].unread == 2)
    #expect(inbox.conversations[0].latest.body == "Look at the notch")
    #expect(inbox.unreadTotal == 3)
  }

  @Test func sameNameInDifferentAppsStaysSeparate() {
    let inbox = NotificationInbox()
      .recording(message("Lena Park", "Hi"))
      .recording(message("Lena Park", "Standup moved", app: "Telegram", bundle: "ru.keepcoder.Telegram"))
    #expect(inbox.conversations.count == 2)
  }

  @Test func ignoresAppsWithoutInlineReply() {
    let mail = NotificationContent(bundleID: "com.apple.mail", appName: "Mail", title: "Stripe", body: "Paid")
    #expect(NotificationInbox().recording(mail).conversations.isEmpty)
  }

  @Test func ignoresMessagesWithoutSender() {
    let noTitle = NotificationContent(bundleID: NotificationApps.messages, appName: "Messages", body: "Hi")
    #expect(NotificationInbox().recording(noTitle).conversations.isEmpty)
  }

  @Test func keepsOnlyTheNewestConversations() {
    var inbox = NotificationInbox()
    for index in 0..<(NotificationInbox.capacity + 5) {
      inbox = inbox.recording(message("Person \(index)", "Hey", at: TimeInterval(index)))
    }
    #expect(inbox.conversations.count == NotificationInbox.capacity)
    #expect(inbox.conversations.first?.sender == "Person \(NotificationInbox.capacity + 4)")
  }

  @Test func markingReadClearsOnlyThatConversation() {
    let inbox = NotificationInbox()
      .recording(message("Sam Rivera", "One"))
      .recording(message("Mia Chen", "Two"))
    let read = inbox.markingRead(inbox.conversations[0].id)
    #expect(read.conversations[0].unread == 0)
    #expect(read.conversations[1].unread == 1)
    #expect(read.unreadTotal == 1)
  }

  @Test func removingAndClearing() {
    let inbox = NotificationInbox()
      .recording(message("Sam Rivera", "One"))
      .recording(message("Mia Chen", "Two"))
    #expect(inbox.removing(inbox.conversations[0].id).conversations.map(\.sender) == ["Sam Rivera"])
    #expect(inbox.cleared().conversations.isEmpty)
  }

  @Test func recordingDoesNotMutateTheOriginal() {
    let empty = NotificationInbox()
    _ = empty.recording(message("Mia Chen", "Hi"))
    #expect(empty.conversations.isEmpty)
  }

  @Test func incomingMessagesBuildTheThreadInOrder() {
    let inbox = NotificationInbox()
      .recording(message("Sam Rivera", "Look", at: 0))
      .recording(message("Sam Rivera", "At the notch", at: 1))
    let thread = inbox.conversations[0].messages
    #expect(thread.map(\.text) == ["Look", "At the notch"])
    #expect(thread.allSatisfy { !$0.fromMe })
  }

  @Test func aSentReplyJoinsTheThreadAsMineAndClearsUnread() {
    let incoming = message("Sam Rivera", "Look", at: 0)
    let inbox = NotificationInbox()
      .recording(incoming)
      .recording(message("Mia Chen", "Dinner?", at: 1))
      .recordingReply("On my way", to: InboxConversation.key(for: incoming), at: start + 2)
    #expect(inbox.conversations[0].sender == "Sam Rivera")
    #expect(inbox.conversations[0].messages.map(\.text) == ["Look", "On my way"])
    #expect(inbox.conversations[0].messages.last?.fromMe == true)
    #expect(inbox.conversations[0].unread == 0)
  }

  @Test func aReplyToARemovedConversationIsDropped() {
    let incoming = message("Sam Rivera", "Look")
    let key = InboxConversation.key(for: incoming)
    let inbox = NotificationInbox().recording(incoming).removing(key).recordingReply("Hi", to: key, at: start)
    #expect(inbox.conversations.isEmpty)
  }

  @Test func threadsKeepOnlyTheNewestMessages() {
    var inbox = NotificationInbox()
    for index in 0..<(InboxConversation.threadCapacity + 3) {
      inbox = inbox.recording(message("Sam Rivera", "Message \(index)", at: TimeInterval(index)))
    }
    let thread = inbox.conversations[0].messages
    #expect(thread.count == InboxConversation.threadCapacity)
    #expect(thread.last?.text == "Message \(InboxConversation.threadCapacity + 2)")
  }

  @Test func initialsComeFromTheSendersName() {
    #expect(InboxConversation.initials(for: "Mia Chen") == "MC")
    #expect(InboxConversation.initials(for: "sam") == "S")
    #expect(InboxConversation.initials(for: "Ana Maria Popescu") == "AP")
    #expect(InboxConversation.initials(for: "+40 712 345 678") == "#")
    #expect(InboxConversation.initials(for: "") == "?")
  }
}

import Foundation
import Combine

import SwiftMatrixSDK

public class NIORoom: ObservableObject {
    public var room: MXRoom

    @Published
    public var summary: NIORoomSummary

    internal var eventCache: [MXEvent] = []

    public var isDirect: Bool {
        room.isDirect
    }

    public var lastMessage: String {
        let lastMessageEvent = eventCache.last {
            $0.type == kMXEventTypeStringRoomMessage
        }
        if lastMessageEvent?.isEdit() ?? false {
            let newContent = lastMessageEvent?.content["m.new_content"]! as? NSDictionary
            return newContent?["body"] as? String ?? ""
        } else {
            return lastMessageEvent?.content["body"] as? String ?? ""
        }
    }

    public init(_ room: MXRoom) {
        self.room = room
        self.summary = NIORoomSummary(room.summary)

        let enumerator = room.enumeratorForStoredMessages//WithType(in: Self.displayedMessageTypes)
        let currentBatch = enumerator?.nextEventsBatch(200) ?? []
        print("Got \(currentBatch.count) events.")

        self.eventCache.append(contentsOf: currentBatch)
        let suite = "group." + ((Bundle.main.infoDictionary?["AppGroup"] as? String) ?? "")
        let defaults = UserDefaults(suiteName: suite)
        var roomList = defaults?.dictionary(forKey: "users")
        if roomList != nil {
            roomList?[room.summary.roomId] = room.summary.displayname!
        } else {
            roomList = [room.summary.roomId!: room.summary.displayname!]
        }

        defaults?.set(roomList, forKey: "users")
    }

    public func add(event: MXEvent, direction: MXTimelineDirection, roomState: MXRoomState?) {
        print("New event of type: \(event.type!)")

        switch direction {
        case .backwards:
            self.eventCache.insert(event, at: 0)
        case .forwards:
            self.eventCache.append(event)
        }

        self.objectWillChange.send()
    }

    public func events() -> EventCollection {
        return EventCollection(eventCache)
    }

    // MARK: Sending Events

    public func send(text: String) {
        guard !text.isEmpty else { return }
        //swiftlint:disable:next redundant_optional_initialization
        var localEcho: MXEvent? = nil
        // TODO: Use localEcho to show sent message until it actually comes back
        room.sendTextMessage(text, localEcho: &localEcho) { _ in
            self.objectWillChange.send()
        }
        self.objectWillChange.send()
    }

    public func react(toEventId eventId: String, emoji: String) {
        // swiftlint:disable:next force_try
        let content = try! ReactionEvent(eventId: eventId, key: emoji).encodeContent()
        //swiftlint:disable:next redundant_optional_initialization
        var localEcho: MXEvent? = nil
        room.sendEvent(.reaction, content: content, localEcho: &localEcho) { _ in
            self.objectWillChange.send()
        }
    }

    public func edit(text: String, eventId: String) {
        guard !text.isEmpty else { return }
        //swiftlint:disable:next redundant_optional_initialization
        var localEcho: MXEvent? = nil
        // swiftlint:disable:next force_try
        let content = try! EditEvent(eventId: eventId, text: text).encodeContent()
        // TODO: Use localEcho to show sent message until it actually comes back
        room.sendMessage(withContent: content, localEcho: &localEcho) { _ in
            self.objectWillChange.send()
        }
        self.objectWillChange.send()
    }

    public func redact(eventId: String, reason: String?) {
        room.redactEvent(eventId, reason: reason) { response in
            self.objectWillChange.send()
        }
    }

    public func sendImage(image: UIImage) {
        guard let imageData = image.jpeg(.lowest) else { return }
        //swiftlint:disable:next redundant_optional_initialization
        var localEcho: MXEvent? = nil
        // TODO: Use localEcho to show sent message until it actually comes back
        room.sendImage(
            data: imageData,
            size: image.size,
            mimeType: "image/jpeg",
            thumbnail: image,
            localEcho: &localEcho
        ) { _ in
            self.objectWillChange.send()
        }
    }

    public func markAllAsRead() {
        room.markAllAsRead()
    }
}

extension NIORoom: Identifiable {
    public var id: ObjectIdentifier {
        room.id
    }
}

extension UIImage {
    public enum JPEGQuality: CGFloat {
        case lowest  = 0
        case low     = 0.25
        case medium  = 0.5
        case high    = 0.75
        case highest = 1
    }

    public func jpeg(_ jpegQuality: JPEGQuality) -> Data? {
        return jpegData(compressionQuality: jpegQuality.rawValue)
    }
}

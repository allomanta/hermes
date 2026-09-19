// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Compile with NotificationService.swift and FMDB, then run on macOS.
import Foundation
import UserNotifications
import FMDB

private class TestService: NotificationService {
    var expireDuringRead = false

    override func getDatabaseKey() -> String? {
        if expireDuringRead { serviceExtensionTimeWillExpire() }
        return nil
    }
}

@main
struct NotificationServiceTests {
    static func main() throws {
        for encoded in [false, true] {
            for expire in [false, true] {
                let service = TestService()
                service.expireDuringRead = expire
                let content = UNMutableNotificationContent()
                content.userInfo = [
                    "room_id": "!room:example.org",
                    "event_id": "$event",
                    "counts": encoded ? "{\"unread\":3}" : ["unread": 3],
                    "devices": encoded
                        ? "[{\"data\":{\"client_name\":\"account\"}}]"
                        : [["data": ["client_name": "account"]]],
                ]
                var deliveries = 0
                let request = UNNotificationRequest(identifier: "test", content: content, trigger: nil)
                service.didReceive(request) { result in
                    deliveries += 1
                    precondition(result.threadIdentifier == "account_!room:example.org")
                    precondition(result.badge == 3)
                    precondition(!result.body.isEmpty)
                }
                service.serviceExtensionTimeWillExpire()
                precondition(deliveries == 1, "Notification delivered more than once")
            }
        }

        for info: [AnyHashable: Any] in [
            [:],
            ["room_id": "!room", "event_id": "$event", "devices": "invalid"],
            ["room_id": "!room", "event_id": "$event", "counts": 3, "devices": false],
        ] {
            let service = TestService()
            let content = UNMutableNotificationContent()
            content.userInfo = info
            var deliveries = 0
            service.didReceive(UNNotificationRequest(identifier: "invalid", content: content, trigger: nil)) { _ in
                deliveries += 1
            }
            service.serviceExtensionTimeWillExpire()
            precondition(deliveries == 1)
        }

        let database = FMDatabase(path: ":memory:")
        precondition(database.open())
        defer { database.close() }
        try database.executeUpdate("CREATE TABLE box_preload_room_states (k TEXT, v TEXT)", values: [])
        try database.executeUpdate("INSERT INTO box_preload_room_states VALUES (?, ?)", values: ["!room|m.room.name|", "invalid"])
        precondition(TestService().getRoomNameFromDatabase(database: database, roomId: "!room") == nil)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("media/account", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cached = directory.appendingPathComponent("notification_example_org_avatar.jpg")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII=")!
        try png.write(to: cached)
        let attachment = try TestService().downloadAttachment(url: "mxc://example.org/avatar", containerPath: root, clientName: "account")
        defer { try? FileManager.default.removeItem(at: attachment.url) }
        precondition(attachment.url != cached)
        let retained = try Data(contentsOf: cached)
        precondition(retained == png)
        print("Passed: completion, expiry, payload formats, malformed cache, and per-account avatar preservation")
    }
}

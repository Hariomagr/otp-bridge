import Foundation
import UserNotifications

enum Notifications {
    static let categoryID = "OTP"
    static let copyActionID = "COPY_CODE"

    static func configure(delegate: UNUserNotificationCenterDelegate) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate

        let copy = UNNotificationAction(
            identifier: copyActionID,
            title: "Copy code",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [copy],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func present(_ msg: OTPMessage) {
        let content = UNMutableNotificationContent()
        content.title = msg.title ?? msg.sender ?? msg.source
        content.body = msg.text
        content.categoryIdentifier = categoryID
        if let code = msg.code { content.userInfo = ["code": code] }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: msg.id,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

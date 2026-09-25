import Foundation
import UserNotifications

enum Notifications {
    static let categoryID = "OTP"
    static let copyActionID = "COPY_CODE"
    static let callCategoryID = "CALL"
    static let rejectActionID = "REJECT_CALL"
    static let acceptActionID = "ACCEPT_CALL"

    static func configure(delegate: UNUserNotificationCenterDelegate) {
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate

        let copy = UNNotificationAction(identifier: copyActionID, title: "Copy code", options: [])
        let otp = UNNotificationCategory(
            identifier: categoryID, actions: [copy], intentIdentifiers: [], options: []
        )

        let accept = UNNotificationAction(identifier: acceptActionID, title: "Accept", options: [])
        let reject = UNNotificationAction(
            identifier: rejectActionID, title: "Reject", options: [.destructive]
        )
        let call = UNNotificationCategory(
            identifier: callCategoryID, actions: [accept, reject], intentIdentifiers: [], options: []
        )

        center.setNotificationCategories([otp, call])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func present(_ msg: OTPMessage) {
        let content = UNMutableNotificationContent()
        content.title = msg.title ?? msg.sender ?? msg.source
        content.body = msg.text
        content.categoryIdentifier = categoryID
        if let code = msg.code { content.userInfo = ["code": code] }
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: msg.id, content: content, trigger: nil)
        )
    }

    /// Incoming calls get Accept/Reject actions on the notification too (the
    /// same controls also live in the menu footer).
    static func presentCall(_ msg: OTPMessage) {
        let content = UNMutableNotificationContent()
        content.title = msg.name ?? msg.number ?? "Unknown"
        content.body = msg.text
        content.sound = .default
        if msg.isIncomingCall {
            content.categoryIdentifier = callCategoryID
            content.userInfo = ["callId": msg.id]
        }

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: msg.id, content: content, trigger: nil)
        )
    }
}

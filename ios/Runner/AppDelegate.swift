import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HermesNotificationCleanup") {
      let channel = FlutterMethodChannel(
        name: "im.hermes/notifications", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "clearRoomNotifications" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let arguments = call.arguments as? [String: Any],
              let clientName = arguments["clientName"] as? String,
              let roomIds = arguments["roomIds"] as? [String] else {
          result(FlutterError(code: "invalid_arguments", message: nil, details: nil))
          return
        }
        let roomIdSet = Set(roomIds)
        let threads = Set(roomIds.map { "\(clientName)_\($0)" })
        let requestedAt = Date()
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
          let identifiers = notifications.compactMap { notification -> String? in
            guard notification.date <= requestedAt else { return nil }
            let content = notification.request.content
            if threads.contains(content.threadIdentifier) {
              return notification.request.identifier
            }
            if let payload = content.userInfo["payload"] as? String {
              let parts = payload.components(separatedBy: "|")
              if parts.count == 3 && parts[0] == clientName && roomIdSet.contains(parts[1]) {
                return notification.request.identifier
              }
            }
            // APNs notifications use arbitrary identifiers and carry Matrix metadata.
            guard let roomId = content.userInfo["room_id"] as? String,
                  roomIdSet.contains(roomId) else { return nil }
            var devices = content.userInfo["devices"] as? [[String: Any]]
            if devices == nil,
               let encoded = content.userInfo["devices"] as? String,
               let data = encoded.data(using: .utf8) {
              devices = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
            }
            let matchesClient = devices?.contains { device in
              (device["data"] as? [String: Any])?["client_name"] as? String == clientName
            } ?? false
            return matchesClient ? notification.request.identifier : nil
          }
          center.removeDeliveredNotifications(withIdentifiers: identifiers)
          DispatchQueue.main.async { result(nil) }
        }
      }
    }
    
    // From https://pub.dev/packages/flutter_local_notifications#-ios-setup
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate  }
}

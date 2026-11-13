import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Set before launch finishes, so a tap that launched the app is delivered. FlutterAppDelegate passes each
    // notification on to the plugins that registered as application delegates (IrisPushPlugin among them).
    UNUserNotificationCenter.current().delegate = self
    IrisPushPlugin.registerCategories()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "IrisPushPlugin") {
      IrisPushPlugin.register(with: registrar)
    }
  }

  /// A tap can arrive before the engine (and so IrisPushPlugin) exists; it is held until the plugin registers.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if IrisPushPlugin.shared == nil, IrisPushPlugin.tapArguments(response) != nil {
      IrisPushPlugin.hold(response)
      completionHandler()
      return
    }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}

/// Iris's push notifications, over the `iris/push` channel (see lib/data/push/ios_push_channel.dart).
///
/// The server sends to APNs directly; the payload's own fields are under `iris` (`kind`, `session_id`, `event_id`).
/// An approval has category `iris.approval`, whose two buttons need the device unlocked and open Iris, which answers
/// the approval itself. Nothing here logs a notification's content or the token.
final class IrisPushPlugin: NSObject, FlutterPlugin {
  static let approvalCategory = "iris.approval"
  private static let actions: Set<String> = ["once", "deny"]

  /// The registered instance, once the engine is up.
  static private(set) var shared: IrisPushPlugin?
  private static var heldBeforeEngine: [[String: Any]] = []

  private let channel: FlutterMethodChannel
  private var token: String?
  private var foregroundChat: String?
  private var dartReady = false
  private var pending: [[String: Any]] = []

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "iris/push", binaryMessenger: registrar.messenger())
    let instance = IrisPushPlugin(channel: channel)
    instance.pending = heldBeforeEngine
    heldBeforeEngine = []
    shared = instance
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  static func registerCategories() {
    let options: UNNotificationActionOptions = [.authenticationRequired, .foreground]
    let approval = UNNotificationCategory(
      identifier: approvalCategory,
      actions: [
        UNNotificationAction(identifier: "once", title: "Approve once", options: options),
        UNNotificationAction(identifier: "deny", title: "Deny", options: options),
      ],
      intentIdentifiers: [],
      options: []
    )
    UNUserNotificationCenter.current().setNotificationCategories([approval])
  }

  static func hold(_ response: UNNotificationResponse) {
    if let arguments = tapArguments(response) { heldBeforeEngine.append(arguments) }
  }

  /// What Dart gets for a tap: the notice's `iris` fields, the button pressed (only `once` / `deny`), and for an
  /// approval the text it showed, to pick the right one when two are waiting. Nil for a notification not from Iris.
  static func tapArguments(_ response: UNNotificationResponse) -> [String: Any]? {
    let content = response.notification.request.content
    guard let iris = content.userInfo["iris"] as? [String: Any] else { return nil }
    var arguments = iris
    if actions.contains(response.actionIdentifier) {
      arguments["action"] = response.actionIdentifier
    }
    if content.categoryIdentifier == approvalCategory, !content.body.isEmpty {
      arguments["command"] = content.body
    }
    return arguments
  }

  // MARK: Dart → iOS

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestPermission":
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async {
          if granted { UIApplication.shared.registerForRemoteNotifications() }
          result(granted)
        }
      }
    case "token":
      result(token)
    case "setForegroundChat":
      foregroundChat = call.arguments as? String
      result(nil)
    case "ready":
      dartReady = true
      let held = pending
      pending = []
      for arguments in held { channel.invokeMethod("tap", arguments: arguments) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: APNs registration

  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    token = hex
    channel.invokeMethod("token", arguments: hex)
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    channel.invokeMethod("tokenError", arguments: (error as NSError).code)
  }

  // MARK: Notifications (passed on by FlutterAppDelegate)

  /// No banner for the chat on screen: the person is reading it. A notification not from Iris is left to others.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    guard let iris = notification.request.content.userInfo["iris"] as? [String: Any] else { return }
    let session = iris["session_id"] as? String
    if let session, session == foregroundChat {
      completionHandler([])
    } else {
      completionHandler([.banner, .list, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard let arguments = IrisPushPlugin.tapArguments(response) else { return }
    if dartReady {
      channel.invokeMethod("tap", arguments: arguments)
    } else {
      pending.append(arguments)
    }
    completionHandler()
  }
}

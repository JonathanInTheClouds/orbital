import ActivityKit
import Flutter
import UIKit

// ── ServerMonitorAttributes ───────────────────────────────────────────────────
// Must match the definition in OrbitalLiveActivity/ServerMonitorAttributes.swift
// exactly. ActivityKit matches by type name across the app and extension.

@available(iOS 16.2, *)
struct ServerMonitorAttributes: ActivityAttributes {
    public typealias ServerMonitorStatus = ContentState

    public struct ContentState: Codable, Hashable {
        var cpuPercent: Double
        var ramPercent: Double
        var diskPercent: Double
        var isConnected: Bool
    }

    var serverName: String
    var host: String
}

// ── LiveActivityManager ───────────────────────────────────────────────────────

@available(iOS 16.2, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var currentActivity: Activity<ServerMonitorAttributes>?

    func start(
        serverName: String,
        host: String,
        cpuPercent: Double,
        ramPercent: Double,
        diskPercent: Double
    ) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }

        if let existing = currentActivity {
            Task { await existing.end(dismissalPolicy: .immediate) }
            currentActivity = nil
        }
        for orphan in Activity<ServerMonitorAttributes>.activities {
            Task { await orphan.end(dismissalPolicy: .immediate) }
        }

        let attributes = ServerMonitorAttributes(serverName: serverName, host: host)
        let initialState = ServerMonitorAttributes.ContentState(
            cpuPercent: cpuPercent,
            ramPercent: ramPercent,
            diskPercent: diskPercent,
            isConnected: true
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            return true
        } catch {
            print("[LiveActivityManager] start failed: \(error)")
            return false
        }
    }

    func update(
        cpuPercent: Double,
        ramPercent: Double,
        diskPercent: Double,
        serverName: String,
        isConnected: Bool
    ) {
        guard let activity = currentActivity else { return }
        let state = ServerMonitorAttributes.ContentState(
            cpuPercent: cpuPercent,
            ramPercent: ramPercent,
            diskPercent: diskPercent,
            isConnected: isConnected
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func stop() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        Task { await activity.end(dismissalPolicy: .immediate) }
    }

    var isActive: Bool { currentActivity != nil }
}

// ── SceneDelegate ─────────────────────────────────────────────────────────────

class SceneDelegate: FlutterSceneDelegate {
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)

        guard let flutterViewController = window?.rootViewController as? FlutterViewController else {
            return
        }

        let channel = FlutterMethodChannel(
            name: "com.orbital/dynamic_island",
            binaryMessenger: flutterViewController.binaryMessenger
        )

        if #available(iOS 16.2, *) {
            setupDynamicIslandChannel(channel)
        } else {
            channel.setMethodCallHandler { _, result in
                result(FlutterError(
                    code: "UNSUPPORTED",
                    message: "Dynamic Island requires iOS 16.1+",
                    details: nil
                ))
            }
        }
    }

    @available(iOS 16.2, *)
    private func setupDynamicIslandChannel(_ channel: FlutterMethodChannel) {
        let manager = LiveActivityManager.shared

        channel.setMethodCallHandler { call, result in
            switch call.method {

            case "startWatching":
                guard
                    let args       = call.arguments as? [String: Any],
                    let serverName = args["serverName"] as? String,
                    let host       = args["host"]       as? String,
                    let cpu        = args["cpu"]        as? Double,
                    let ram        = args["ram"]        as? Double,
                    let disk       = args["disk"]       as? Double
                else {
                    result(FlutterError(code: "INVALID_ARGS", message: "startWatching requires serverName, host, cpu, ram, disk", details: nil))
                    return
                }
                result(manager.start(serverName: serverName, host: host, cpuPercent: cpu, ramPercent: ram, diskPercent: disk))

            case "updateMetrics":
                guard
                    let args       = call.arguments as? [String: Any],
                    let serverName = args["serverName"] as? String,
                    let cpu        = args["cpu"]        as? Double,
                    let ram        = args["ram"]        as? Double,
                    let disk       = args["disk"]       as? Double
                else {
                    result(FlutterError(code: "INVALID_ARGS", message: "updateMetrics requires serverName, cpu, ram, disk", details: nil))
                    return
                }
                manager.update(
                    cpuPercent:  cpu,
                    ramPercent:  ram,
                    diskPercent: disk,
                    serverName:  serverName,
                    isConnected: args["isConnected"] as? Bool ?? true
                )
                result(nil)

            case "stopWatching":
                manager.stop()
                result(nil)

            case "isSupported":
                result(ActivityAuthorizationInfo().areActivitiesEnabled)

            case "isWatching":
                result(manager.isActive)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}

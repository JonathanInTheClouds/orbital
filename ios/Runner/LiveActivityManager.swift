import ActivityKit
import Foundation

// ── LiveActivityManager ───────────────────────────────────────────────────────
//
// Manages the single Live Activity that Orbital can run at a time.
// Called exclusively from the Flutter MethodChannel handler in AppDelegate.

@available(iOS 16.1, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    private var currentActivity: Activity<ServerMonitorAttributes>?

    // MARK: – Public API

    /// Starts a new Live Activity. Stops any existing one first.
    /// Returns `true` on success, `false` if Live Activities are disabled or
    /// the request fails.
    func start(
        serverName: String,
        host: String,
        cpuPercent: Double,
        ramPercent: Double,
        diskPercent: Double
    ) -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return false
        }

        // End any previous activity immediately so we don't accumulate stale
        // activities in the system list.
        if let existing = currentActivity {
            Task { await existing.end(dismissalPolicy: .immediate) }
            currentActivity = nil
        }
        // Also sweep up any orphaned activities from previous app launches.
        for orphan in Activity<ServerMonitorAttributes>.activities {
            Task { await orphan.end(dismissalPolicy: .immediate) }
        }

        let attributes = ServerMonitorAttributes(
            serverName: serverName,
            host: host
        )
        let initialState = ServerMonitorAttributes.ContentState(
            cpuPercent: cpuPercent,
            ramPercent: ramPercent,
            diskPercent: diskPercent,
            isConnected: true
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            return true
        } catch {
            print("[LiveActivityManager] start failed: \(error)")
            return false
        }
    }

    /// Pushes fresh metrics to the running Live Activity.
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
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    /// Ends the Live Activity and dismisses it from the island immediately.
    func stop() {
        guard let activity = currentActivity else { return }
        currentActivity = nil
        Task { await activity.end(dismissalPolicy: .immediate) }
    }

    /// Whether a Live Activity is currently running.
    var isActive: Bool { currentActivity != nil }
}

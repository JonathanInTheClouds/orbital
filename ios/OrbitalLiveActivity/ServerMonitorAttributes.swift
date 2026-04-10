import ActivityKit
import Foundation

// ── ServerMonitorAttributes ───────────────────────────────────────────────────
//
// Defines the static (attributes) and dynamic (ContentState) data shown
// in the Live Activity / Dynamic Island.
//
// Static data (doesn't change after the activity is started):
//   • serverName – display name of the server
//   • host       – hostname or IP address
//
// Dynamic data (updated whenever metrics refresh):
//   • cpuPercent   – CPU usage 0–100
//   • ramPercent   – RAM usage 0–100
//   • diskPercent  – Disk usage 0–100
//   • isConnected  – false if the SSH connection dropped

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

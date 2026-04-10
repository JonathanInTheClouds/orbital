import ActivityKit
import SwiftUI
import WidgetKit

// ═════════════════════════════════════════════════════════════════════════════
// MARK: – Shared sub-views
// ═════════════════════════════════════════════════════════════════════════════

/// A single metric shown as a colored number + small label underneath.
private struct MetricColumn: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
    }
}

/// Thin horizontal progress bar.
private struct MiniBar: View {
    let value: Double   // 0–100
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(value / 100))
            }
        }
        .frame(height: 3)
    }
}

/// A metric column with a bar underneath, used in the expanded island view.
private struct ExpandedMetricCell: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            MiniBar(value: value, color: color)
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// MARK: – Lock Screen banner view
// ═════════════════════════════════════════════════════════════════════════════

struct OrbitalLockScreenView: View {
    let state: ServerMonitorAttributes.ContentState
    let attrs: ServerMonitorAttributes

    var body: some View {
        HStack(spacing: 16) {
            // Server identity
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isConnected ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(attrs.serverName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(attrs.host)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            Spacer()

            // Metric pills
            HStack(spacing: 14) {
                MetricColumn(label: "CPU", value: state.cpuPercent, color: .cyan)
                MetricColumn(label: "RAM", value: state.ramPercent, color: Color(red: 0.6, green: 0.4, blue: 1.0))
                MetricColumn(label: "DISK", value: state.diskPercent, color: Color(red: 1.0, green: 0.6, blue: 0.2))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.black.opacity(0.35))
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// MARK: – Widget configuration
// ═════════════════════════════════════════════════════════════════════════════

struct OrbitalLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ServerMonitorAttributes.self) { context in
            // ── Lock Screen / StandBy banner ──────────────────────────────
            OrbitalLockScreenView(
                state: context.state,
                attrs: context.attributes
            )

        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded (user long-presses the island) ───────────────
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.serverName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(context.attributes.host)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                    .padding(.leading, 6)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(context.state.isConnected ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                        Text(context.state.isConnected ? "Live" : "Lost")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.trailing, 6)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 0) {
                        Spacer()
                        ExpandedMetricCell(
                            label: "CPU",
                            value: context.state.cpuPercent,
                            color: .cyan
                        )
                        Spacer()
                        // Subtle divider
                        Rectangle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 1, height: 36)
                        Spacer()
                        ExpandedMetricCell(
                            label: "RAM",
                            value: context.state.ramPercent,
                            color: Color(red: 0.6, green: 0.4, blue: 1.0)
                        )
                        Spacer()
                        Rectangle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 1, height: 36)
                        Spacer()
                        ExpandedMetricCell(
                            label: "Disk",
                            value: context.state.diskPercent,
                            color: Color(red: 1.0, green: 0.6, blue: 0.2)
                        )
                        Spacer()
                    }
                    .padding(.bottom, 10)
                    .padding(.top, 4)
                }

            } compactLeading: {
                // ── Compact – left side: dot + server name ────────────────
                HStack(spacing: 4) {
                    Circle()
                        .fill(context.state.isConnected ? .green : .red)
                        .frame(width: 5, height: 5)
                    Text(context.attributes.serverName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 80, alignment: .leading)
                }
                .padding(.leading, 4)

            } compactTrailing: {
                // ── Compact – right side: CPU % ───────────────────────────
                Text("\(Int(context.state.cpuPercent.rounded()))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
                    .padding(.trailing, 4)

            } minimal: {
                // ── Minimal (another activity is leading) ─────────────────
                Text("\(Int(context.state.cpuPercent.rounded()))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.cyan)
            }
            .keylineTint(.cyan)
        }
    }
}

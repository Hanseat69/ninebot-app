//
//  ScooterLiveActivity.swift
//  Tempo, Akku und Strecke auf dem Sperrbildschirm und in der Dynamic Island.
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NinebotWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScooterLiveActivity()
    }
}

struct ScooterLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScooterActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SpeedText(speed: context.state.speed, font: .title)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BatteryText(battery: context.state.battery)
                        .font(.title3)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(String(format: "%.1f km", locale: Locale.current, context.state.distanceKm),
                              systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        Spacer()
                        Label {
                            Text(context.attributes.start, style: .timer)
                        } icon: {
                            Image(systemName: "clock")
                        }
                        if let range = context.state.rangeKm {
                            Spacer()
                            Label(String(format: "%.0f km", locale: Locale.current, range), systemImage: "fuelpump")
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                SpeedText(speed: context.state.speed, font: .caption)
            } compactTrailing: {
                BatteryText(battery: context.state.battery)
                    .font(.caption)
            } minimal: {
                BatteryText(battery: context.state.battery)
                    .font(.caption2)
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<ScooterActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                SpeedText(speed: context.state.speed, font: .largeTitle)
                Text(context.attributes.scooterName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                BatteryText(battery: context.state.battery)
                    .font(.title3)
                Text(String(format: "%.1f km", locale: Locale.current, context.state.distanceKm))
                Text(context.attributes.start, style: .timer)
                    .monospacedDigit()
            }
            .font(.subheadline)
        }
        .foregroundColor(.white)
        .padding()
    }
}

private struct SpeedText: View {
    let speed: Double?
    let font: Font

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(speed.map { String(format: "%.0f", $0) } ?? "–")
                .font(font)
                .bold()
                .monospacedDigit()
            Text("km/h").font(.caption2)
        }
    }
}

private struct BatteryText: View {
    let battery: Int?

    var body: some View {
        Label(battery.map { "\($0) %" } ?? "–", systemImage: symbol)
            .foregroundColor(color)
    }

    private var symbol: String {
        switch battery ?? 100 {
        case ..<15: return "battery.0"
        case ..<40: return "battery.25"
        case ..<65: return "battery.50"
        case ..<90: return "battery.75"
        default: return "battery.100"
        }
    }

    private var color: Color {
        guard let battery = battery else { return .white }
        return battery < 15 ? .red : (battery < 30 ? .orange : .green)
    }
}

//
//  LiveActivityController.swift
//  Startet, aktualisiert und beendet die Anzeige auf Sperrbildschirm und
//  Dynamic Island. iOS erlaubt das Starten nur, solange die App im
//  Vordergrund ist; läuft eine Fahrt schon, wird beim Öffnen nachgestartet.
//

import Foundation
import ActivityKit

final class LiveActivityController {

    private var activity: Any?
    private var lastUpdate = Date.distantPast

    var isRunning: Bool { activity != nil }

    func start(name: String, start: Date, state: LiveState) {
        guard #available(iOS 16.1, *), activity == nil,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ScooterActivityAttributes(scooterName: name, start: start)
        do {
            if #available(iOS 16.2, *) {
                activity = try Activity.request(attributes: attributes,
                                                content: ActivityContent(state: state.content, staleDate: nil),
                                                pushType: nil)
            } else {
                activity = try Activity.request(attributes: attributes, contentState: state.content, pushType: nil)
            }
        } catch {
            print("Live Activity nicht gestartet: \(error.localizedDescription)")
        }
    }

    /// Höchstens alle 3 Sekunden, damit iOS nicht drosselt.
    func update(_ state: LiveState) {
        guard #available(iOS 16.1, *),
              let activity = activity as? Activity<ScooterActivityAttributes>,
              Date().timeIntervalSince(lastUpdate) >= 3 else { return }
        lastUpdate = Date()
        Task {
            if #available(iOS 16.2, *) {
                await activity.update(ActivityContent(state: state.content, staleDate: nil))
            } else {
                await activity.update(using: state.content)
            }
        }
    }

    func end() {
        guard #available(iOS 16.1, *),
              let activity = activity as? Activity<ScooterActivityAttributes> else { return }
        self.activity = nil
        Task {
            if #available(iOS 16.2, *) {
                await activity.end(nil, dismissalPolicy: .immediate)
            } else {
                await activity.end(using: nil, dismissalPolicy: .immediate)
            }
        }
    }
}

/// Die angezeigten Werte, unabhängig von der iOS-Version.
struct LiveState {
    var speed: Double?
    var battery: Int?
    var distanceKm: Double
    var rangeKm: Double?

    @available(iOS 16.1, *)
    var content: ScooterActivityAttributes.ContentState {
        .init(speed: speed, battery: battery, distanceKm: distanceKm, rangeKm: rangeKm)
    }
}

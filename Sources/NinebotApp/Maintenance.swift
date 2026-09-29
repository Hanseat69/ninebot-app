//
//  Maintenance.swift
//  Wartungserinnerungen nach Kilometerstand des Scooters.
//

import Foundation
import SwiftUI
import UserNotifications

struct MaintenanceItem: Codable, Identifiable {
    let id: String
    var title: String
    var intervalKm: Double
    var lastServiceKm: Double?
    var lastServiceDate: Date?
    var notified = false

    /// Positiv: noch so viele km bis fällig. Negativ: seit so vielen km überfällig.
    func remainingKm(at odometer: Double) -> Double? {
        guard let last = lastServiceKm else { return nil }
        return last + intervalKm - odometer
    }

    static let defaults: [MaintenanceItem] = [
        MaintenanceItem(id: "tyre-pressure", title: "Reifendruck prüfen", intervalKm: 150),
        MaintenanceItem(id: "screws", title: "Schrauben nachziehen (Lenker, Klappmechanismus)", intervalKm: 300),
        MaintenanceItem(id: "brakes", title: "Bremsen prüfen und einstellen", intervalKm: 500),
        MaintenanceItem(id: "tyres", title: "Reifenprofil und -zustand prüfen", intervalKm: 1000),
    ]
}

final class MaintenanceStore: ObservableObject {

    @Published private(set) var items: [MaintenanceItem]

    private static let key = "maintenance"

    init() {
        if let data = UserDefaults.standard.data(forKey: MaintenanceStore.key),
           let saved = try? JSONDecoder().decode([MaintenanceItem].self, from: data) {
            items = saved
        } else {
            items = MaintenanceItem.defaults
        }
    }

    func dueCount(at odometer: Double?) -> Int {
        guard let odometer = odometer else { return 0 }
        return items.filter { ($0.remainingKm(at: odometer) ?? 1) <= 0 }.count
    }

    /// Bei jedem neuen Kilometerstand: Startwert setzen und fällige Punkte melden.
    func update(odometer: Double) {
        var changed = false
        for i in items.indices {
            if items[i].lastServiceKm == nil {
                items[i].lastServiceKm = odometer
                changed = true
            }
            if let remaining = items[i].remainingKm(at: odometer), remaining <= 0, !items[i].notified {
                items[i].notified = true
                changed = true
                notify(items[i])
            }
        }
        if changed { save() }
    }

    func markDone(_ id: String, odometer: Double?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].lastServiceKm = odometer ?? items[i].lastServiceKm
        items[i].lastServiceDate = Date()
        items[i].notified = false
        save()
    }

    func setInterval(_ id: String, km: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].intervalKm = km
        items[i].notified = false
        save()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notify(_ item: MaintenanceItem) {
        let content = UNMutableNotificationContent()
        content.title = "Wartung fällig"
        content.body = item.title
        content.sound = .default
        let request = UNNotificationRequest(identifier: "maintenance-\(item.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: MaintenanceStore.key)
        }
    }
}

struct MaintenanceView: View {
    @EnvironmentObject private var model: ScooterModel
    @EnvironmentObject private var maintenance: MaintenanceStore

    var body: some View {
        List {
            Section {
                if let odometer = model.odometer {
                    ValueRow(title: "Kilometerstand", value: Format.kilometers(odometer))
                } else {
                    Text("Kilometerstand noch unbekannt — einmal mit dem Scooter verbinden.")
                        .foregroundColor(.secondary)
                }
            }

            ForEach(maintenance.items) { item in
                Section {
                    Text(item.title).font(.headline)
                    if let odometer = model.odometer, let remaining = item.remainingKm(at: odometer) {
                        if remaining <= 0 {
                            Label("Überfällig seit \(Format.kilometers(-remaining))", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        } else {
                            Text("Fällig in \(Format.kilometers(remaining))")
                                .foregroundColor(.secondary)
                        }
                    }
                    if let date = item.lastServiceDate {
                        ValueRow(title: "Zuletzt erledigt", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                    Stepper(value: Binding(
                        get: { item.intervalKm },
                        set: { maintenance.setInterval(item.id, km: $0) }
                    ), in: 50...5000, step: 50) {
                        Text("Alle \(Int(item.intervalKm)) km")
                    }
                    Button("Erledigt") { maintenance.markDone(item.id, odometer: model.odometer) }
                        .disabled(model.odometer == nil)
                }
            }
        }
        .navigationTitle("Wartung")
        .onAppear { maintenance.requestNotificationPermission() }
    }
}

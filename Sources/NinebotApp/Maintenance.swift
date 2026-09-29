//
//  Maintenance.swift
//  Wartungserinnerungen nach dem „Empfohlenen Wartungsplan“ aus dem
//  Produkt-Handbuch Segway-Ninebot KickScooter F2 / F2 Plus / F2 Pro
//  (Abschnitt 3). Fällig ist ein Punkt, sobald Kilometer- ODER Zeitintervall
//  erreicht ist — je nachdem, was zuerst eintritt.
//

import Foundation
import SwiftUI
import UserNotifications

struct MaintenanceItem: Codable, Identifiable {
    let id: String
    let title: String
    let details: String
    var intervalKm: Double?
    var intervalMonths: Int?
    var lastServiceKm: Double?
    var lastServiceDate: Date?
    var notified = false

    /// Positiv: noch so viele km bis fällig. Negativ: seit so vielen km überfällig.
    func remainingKm(at odometer: Double?) -> Double? {
        guard let interval = intervalKm, let last = lastServiceKm, let odometer = odometer else { return nil }
        return last + interval - odometer
    }

    var dueDate: Date? {
        guard let months = intervalMonths, let last = lastServiceDate else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: last)
    }

    func isDue(at odometer: Double?) -> Bool {
        if let km = remainingKm(at: odometer), km <= 0 { return true }
        if let date = dueDate, date <= Date() { return true }
        return false
    }

    var intervalText: String {
        switch (intervalMonths, intervalKm) {
        case let (m?, km?): return "Alle \(m) Monate oder \(Format.kilometers(km))"
        case let (m?, nil): return "Alle \(m) Monate"
        case let (nil, km?): return "Alle \(Format.kilometers(km))"
        default: return ""
        }
    }
}

extension MaintenanceItem {
    private static func item(_ id: String, _ title: String, _ details: String,
                             months: Int?, km: Double?) -> MaintenanceItem {
        MaintenanceItem(id: id, title: title, details: details, intervalKm: km, intervalMonths: months)
    }

    /// Laut Handbuch jeweils das kürzeste Intervall, in dem der Punkt vorkommt.
    static let manufacturerPlan: [MaintenanceItem] = [
        // Alle 3 Monate
        item("clean", "Rahmen reinigen",
             "Den Rahmen mit einem weichen, feuchten Tuch sauber wischen.", months: 3, km: nil),
        item("tyre-pressure", "Reifendruck prüfen",
             "Laut Wartungsplan auf 50–55 psi (ca. 3,4–3,8 bar) aufpumpen. Achtung: Die technischen Daten im selben Handbuch nennen 42–48 psi (ca. 2,9–3,3 bar). Im Zweifel die Angabe auf der Reifenflanke beachten oder beim Händler nachfragen.",
             months: 3, km: nil),
        item("handlebar-screws", "Schrauben Lenker und Vorbau",
             "Die Schrauben festziehen, die Lenker und Vorbau verbinden. Drehmoment 5,5 ± 0,5 Nm.", months: 3, km: nil),

        // Alle 6 Monate oder 500 km
        item("tyre-wear", "Reifenverschleiß",
             "Prüfen, ob die Reifen gerissen, verformt oder stark abgenutzt sind.", months: 6, km: 500),
        item("folding-screws", "Schrauben Klappmechanismus",
             "Die beiden Schrauben an Vorderradgabel und Klappmechanismus festziehen, Drehmoment 10 Nm. Wackelt der Vorbau während der Fahrt: die Schrauben am Klappmechanismus im zusammengeklappten Zustand festziehen, Drehmoment 12,5 ± 1 Nm.",
             months: 6, km: 500),
        item("disc-screws", "Schrauben Scheibenbremse",
             "Die Schrauben an der Bremsscheiben-Baugruppe festziehen. Drehmoment 7,7 ± 0,2 Nm.", months: 6, km: 500),
        item("brake-adjust", "Bremse einstellen",
             "Ist die Bremse zu fest oder zu locker: Schraube am Bremssattel mit dem 4-mm-Inbusschlüssel lösen, die freiliegende Länge des Bremszugs leicht anpassen und die Schraube wieder festziehen.",
             months: 6, km: 500),
        item("function-check", "Funktionsprüfung",
             "Rücklicht beim Bremsen, Scheinwerfer, Blinker links/rechts, Armaturenbrett, Buzzer beim Ein-/Ausschalten, Hupe (F2 Pro), Klingel, Gashebel (kehrt nach dem Loslassen zurück), Laden (Anzeige am Armaturenbrett, Ladegerät-LED rot = lädt, grün = voll) und Bedientasten (3-mal ohne Fehler).",
             months: 6, km: 500),
        item("firmware", "Firmware und Fehlercodes",
             "In der Segway-Ninebot-App die Firmware auf die neueste Version bringen und prüfen, ob Fehlercodes gemeldet werden.",
             months: 6, km: 500),

        // Alle 12 Monate oder 1.000 km
        item("control-screws", "Schrauben Gasgriff, Bremshebel, Vorbauoberteil",
             "Gasgriff 3,5 ± 0,1 Nm, Bremshebel 5,5 ± 0,1 Nm, Vorbauoberteil 10 ± 0,5 Nm.", months: 12, km: 1000),
        item("hub-motor", "Nabenmotor",
             "Beim Beschleunigen und Bremsen prüfen, ob der Motor stockt oder ungewöhnliche Geräusche macht.",
             months: 12, km: 1000),
        item("front-wheel", "Vorderrad",
             "Prüfen, ob das Vorderrad blockiert oder wackelt, oder die Achse Spiel hat.", months: 12, km: 1000),
        item("brake-pads", "Bremsbeläge",
             "Räder drehen: Der Bremssattel soll zur Scheibe ausgerichtet sein, die Beläge dürfen nicht schleifen.",
             months: 12, km: 1000),
        item("steering", "Lenkung",
             "Links- und Rechtskurven testen (Lenkwinkel 60°): kein Widerstand, keine Verzögerung beim Lenken.",
             months: 12, km: 1000),

        // Langfristig
        item("parts-36", "Wichtige Teile prüfen",
             "Nach 3 Jahren oder 15.000 km müssen auffällige Teile ersetzt werden: Regler, Nabenmotor, Vorderrad, Gas- und Bremshebel, Vorderradgabel, Klappmechanismus, Bremsbeläge, Scheibenbremse, Armaturenbrett-Abdeckung.",
             months: 36, km: 15000),
        item("battery", "Akku ersetzen",
             "Der Akku muss nach 500 Lade-/Entladezyklen oder mehr als 10.000 km Gesamtlaufleistung ersetzt werden. Bei längerer Lagerung alle 60 Tage aufladen.",
             months: nil, km: 10000),
    ]
}

final class MaintenanceStore: ObservableObject {

    @Published private(set) var items: [MaintenanceItem]

    private static let key = "maintenance.manufacturer"

    init() {
        let plan = MaintenanceItem.manufacturerPlan
        if let data = UserDefaults.standard.data(forKey: MaintenanceStore.key),
           let saved = try? JSONDecoder().decode([MaintenanceItem].self, from: data) {
            // Gespeicherten Stand übernehmen, Texte und neue Punkte aus dem Plan.
            items = plan.map { planned in
                guard let old = saved.first(where: { $0.id == planned.id }) else { return planned }
                var item = planned
                item.intervalKm = old.intervalKm
                item.intervalMonths = old.intervalMonths
                item.lastServiceKm = old.lastServiceKm
                item.lastServiceDate = old.lastServiceDate
                item.notified = old.notified
                return item
            }
        } else {
            items = plan
        }
    }

    func dueCount(at odometer: Double?) -> Int {
        items.filter { $0.isDue(at: odometer) }.count
    }

    /// Bei jedem neuen Kilometerstand: Startwerte setzen und fällige Punkte melden.
    func update(odometer: Double) {
        var changed = false
        for i in items.indices {
            if items[i].lastServiceKm == nil {
                items[i].lastServiceKm = odometer
                changed = true
            }
            if items[i].lastServiceDate == nil {
                items[i].lastServiceDate = Date()
                changed = true
            }
            if items[i].isDue(at: odometer), !items[i].notified {
                items[i].notified = true
                changed = true
                notifyNow(items[i])
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

    func setIntervalKm(_ id: String, km: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].intervalKm = km
        items[i].notified = false
        save()
    }

    func resetToManufacturerPlan() {
        for i in items.indices {
            if let planned = MaintenanceItem.manufacturerPlan.first(where: { $0.id == items[i].id }) {
                items[i].intervalKm = planned.intervalKm
                items[i].intervalMonths = planned.intervalMonths
            }
        }
        save()
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func notifyNow(_ item: MaintenanceItem) {
        let content = UNMutableNotificationContent()
        content.title = "Wartung fällig"
        content.body = item.title
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "maintenance-now-\(item.id)", content: content, trigger: nil))
    }

    /// Zeitbasierte Erinnerungen fest einplanen — kommen auch, wenn die App nicht läuft.
    private func scheduleDateReminders() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: items.map { "maintenance-date-\($0.id)" })
        for item in items {
            guard let due = item.dueDate, due > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Wartung fällig"
            content.body = item.title
            content.sound = .default
            var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
            components.hour = 10
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: "maintenance-date-\(item.id)", content: content, trigger: trigger))
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: MaintenanceStore.key)
        }
        scheduleDateReminders()
    }
}

struct MaintenanceView: View {
    @EnvironmentObject private var model: ScooterModel
    @EnvironmentObject private var maintenance: MaintenanceStore

    private var groups: [(title: String, items: [MaintenanceItem])] {
        let order = [3, 6, 12, 36, 0]
        return order.compactMap { months in
            let items = maintenance.items.filter { ($0.intervalMonths ?? 0) == months }
            guard !items.isEmpty else { return nil }
            return (items[0].intervalText, items)
        }
    }

    var body: some View {
        List {
            Section {
                if let odometer = model.odometer {
                    ValueRow(title: "Kilometerstand", value: Format.kilometers(odometer))
                } else {
                    Text("Kilometerstand noch unbekannt — einmal mit dem Scooter verbinden.")
                        .foregroundColor(.secondary)
                }
                ValueRow(title: "Fällig", value: "\(maintenance.dueCount(at: model.odometer)) von \(maintenance.items.count)")
            } footer: {
                Text("Nach dem „Empfohlenen Wartungsplan“ im Produkt-Handbuch F2 / F2 Plus / F2 Pro. Fällig ist ein Punkt nach Kilometern oder Zeit, je nachdem, was zuerst eintritt. Laut Handbuch kann der Händler dafür eine Servicegebühr berechnen.")
            }

            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        NavigationLink {
                            MaintenanceDetailView(itemID: item.id)
                        } label: {
                            MaintenanceRow(item: item, odometer: model.odometer)
                        }
                    }
                }
            }

            Section {
                Button("Intervalle auf Herstellerwerte zurücksetzen") {
                    maintenance.resetToManufacturerPlan()
                }
            }
        }
        .navigationTitle("Wartung")
        .onAppear { maintenance.requestNotificationPermission() }
    }
}

private struct MaintenanceRow: View {
    let item: MaintenanceItem
    let odometer: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(item.title)
                if item.isDue(at: odometer) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                }
            }
            Text(status).font(.caption).foregroundColor(item.isDue(at: odometer) ? .orange : .secondary)
        }
    }

    private var status: String {
        var parts: [String] = []
        if let km = item.remainingKm(at: odometer) {
            parts.append(km <= 0 ? "seit \(Format.kilometers(-km)) überfällig" : "in \(Format.kilometers(km))")
        }
        if let due = item.dueDate {
            parts.append(due <= Date() ? "seit \(due.formatted(date: .abbreviated, time: .omitted)) fällig"
                                       : "bis \(due.formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.isEmpty ? "Startwert wird beim ersten Verbinden gesetzt" : "Fällig " + parts.joined(separator: " oder ")
    }
}

private struct MaintenanceDetailView: View {
    @EnvironmentObject private var model: ScooterModel
    @EnvironmentObject private var maintenance: MaintenanceStore
    @Environment(\.dismiss) private var dismiss
    let itemID: String

    var body: some View {
        if let item = maintenance.items.first(where: { $0.id == itemID }) {
            List {
                Section("Laut Handbuch") {
                    Text(item.details)
                    ValueRow(title: "Intervall", value: item.intervalText)
                }
                Section {
                    MaintenanceRow(item: item, odometer: model.odometer)
                    if let date = item.lastServiceDate {
                        ValueRow(title: "Zuletzt erledigt", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let km = item.intervalKm {
                        Stepper(value: Binding(
                            get: { km },
                            set: { maintenance.setIntervalKm(item.id, km: $0) }
                        ), in: 100...20000, step: 100) {
                            Text("Eigenes Intervall: \(Format.kilometers(km))")
                        }
                    }
                }
                Section {
                    Button("Als erledigt markieren") {
                        maintenance.markDone(item.id, odometer: model.odometer)
                        dismiss()
                    }
                }
            }
            .navigationTitle(item.title)
        }
    }
}

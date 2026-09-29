//
//  BatteryView.swift
//  Tab „Akku“: Verlauf des Akkuzustands und Verbrauch pro Fahrt.
//

import SwiftUI
import Charts

struct BatteryView: View {
    @EnvironmentObject private var store: TripStore

    private var healthPoints: [BatterySnapshot] {
        store.snapshots.filter { $0.health != nil }
    }

    /// Die letzten 30 Fahrten mit aussagekräftigem Verbrauch, älteste zuerst.
    private var consumptionTrips: [Trip] {
        Array(store.trips.filter { $0.consumptionPerKm != nil }.prefix(30).reversed())
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if healthPoints.count < 2 {
                        Text("Wird bei jeder Verbindung einmal pro Tag notiert. Ab zwei Messungen erscheint hier ein Verlauf.")
                            .foregroundColor(.secondary)
                    } else {
                        Chart(healthPoints) { point in
                            LineMark(x: .value("Datum", point.date), y: .value("Zustand", point.health ?? 0))
                            PointMark(x: .value("Datum", point.date), y: .value("Zustand", point.health ?? 0))
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 200)
                    }
                    if let last = healthPoints.last, let health = last.health {
                        ValueRow(title: "Zuletzt", value: "\(health) % (\(last.date.formatted(date: .abbreviated, time: .omitted)))")
                    }
                } header: {
                    Text("Akkuzustand")
                } footer: {
                    Text("Wie viel Kapazität der Akku im Vergleich zum Neuzustand noch hat, laut Akku-Steuerung des Scooters.")
                }

                Section {
                    if consumptionTrips.isEmpty {
                        Text("Erscheint nach den ersten Fahrten ab 0,5 km.")
                            .foregroundColor(.secondary)
                    } else {
                        Chart(consumptionTrips) { trip in
                            BarMark(x: .value("Fahrt", trip.start, unit: .day),
                                    y: .value("% pro km", trip.consumptionPerKm ?? 0))
                        }
                        .frame(height: 200)
                        let average = consumptionTrips.compactMap(\.consumptionPerKm).reduce(0, +)
                            / Double(consumptionTrips.count)
                        ValueRow(title: "Durchschnitt",
                                 value: String(format: "%.1f %% Akku pro km", locale: Locale.current, average))
                        if average > 0 {
                            ValueRow(title: "Reichweite bei 100 %",
                                     value: Format.kilometers(100 / average))
                        }
                    }
                } header: {
                    Text("Verbrauch pro Fahrt")
                }
            }
            .navigationTitle("Akku")
        }
    }
}

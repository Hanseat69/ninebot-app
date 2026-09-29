//
//  ScooterView.swift
//  Tab „Scooter“: verbinden, Live-Werte, Einstellungen, Automatik.
//

import SwiftUI

struct ScooterView: View {
    @EnvironmentObject private var model: ScooterModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        if model.isBusy { ProgressView() }
                        Text(model.statusText)
                    }
                    if let message = model.message {
                        Text(message).font(.footnote).foregroundColor(.secondary)
                    }
                }

                switch model.state {
                case .authenticated:
                    liveSection
                    settingsSection
                    vehicleSection
                    Section {
                        Button("Trennen", role: .destructive) { model.disconnect() }
                    }
                case .idle, .failed:
                    searchSection
                default:
                    Section {
                        Button("Abbrechen", role: .destructive) { model.disconnect() }
                    }
                }

                automationSection
            }
            .navigationTitle(model.connectedName ?? "Ninebot")
        }
    }

    // MARK: - Nicht verbunden

    private var searchSection: some View {
        Section {
            Button(model.isScanning ? "Suche läuft …" : "Scooter suchen") {
                model.startScan()
            }
            .disabled(model.isScanning)

            ForEach(model.scooters) { scooter in
                Button {
                    model.connect(to: scooter)
                } label: {
                    HStack {
                        Text(scooter.name)
                        Spacer()
                        Text("\(scooter.rssi) dBm").foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Scooter in der Nähe")
        } footer: {
            Text("Scooter einschalten und in der Nähe bleiben. Beim ersten Verbinden fordert die App dich auf, den Power-Knopf am Scooter kurz zu drücken.")
        }
    }

    // MARK: - Verbunden

    private var liveSection: some View {
        Section {
            if model.activeTrip != nil {
                Label("Fahrt wird aufgezeichnet", systemImage: "record.circle")
                    .foregroundColor(.red)
            }
            if let speed = model.gpsSpeed {
                ValueRow(title: "Geschwindigkeit (GPS)", value: Format.speed(speed))
            }
            ForEach(model.liveValues) { value in
                ValueRow(title: value.title, value: value.text)
            }
        } header: {
            Text("Live")
        }
    }

    private var settingsSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("Tempolimit (Begrenzungsmodus)")
                HStack {
                    Text("\(Int(model.speedLimit)) km/h")
                        .monospacedDigit()
                        .frame(width: 70, alignment: .leading)
                    Slider(value: $model.speedLimit, in: ScooterModel.speedLimitRange, step: 1)
                }
                Button("Limit setzen") { model.applySpeedLimit() }
                    .buttonStyle(.bordered)
            }

            Picker("Rekuperation (KERS)", selection: Binding(
                get: { model.kersLevel ?? 0 },
                set: { model.setKers($0) }
            )) {
                ForEach(0..<ScooterModel.kersLevels.count, id: \.self) { level in
                    Text(ScooterModel.kersLevels[level]).tag(level)
                }
            }
            .disabled(model.kersLevel == nil)

            Toggle("Tempomat", isOn: Binding(
                get: { model.cruiseControl ?? false },
                set: { model.setCruiseControl($0) }
            ))
            .disabled(model.cruiseControl == nil)

            Toggle("Rücklicht", isOn: Binding(
                get: { model.tailLight ?? false },
                set: { model.setTailLight($0) }
            ))
            .disabled(model.tailLight == nil)
        } header: {
            Text("Einstellungen")
        } footer: {
            Text("Die Referenz liest diese Werte nur; das Schreiben ist ungetestet. Nach jeder Änderung liest die App den Wert zur Kontrolle neu aus. Der Regler endet bei 20 km/h, dem gesetzlichen Maximum in Deutschland (eKFV).")
        }
    }

    private var vehicleSection: some View {
        Section {
            ForEach(model.values) { value in
                ValueRow(title: value.title, value: value.text)
            }
            Button(model.isReading ? "Liest …" : "Aktualisieren") { model.refresh() }
                .disabled(model.isReading)
        } header: {
            Text("Fahrzeug")
        }
    }

    // MARK: - Automatik

    private var automationSection: some View {
        Section {
            Toggle("Automatisch verbinden", isOn: $model.autoConnect)
            if let known = model.knownScooter {
                ValueRow(title: "Mein Scooter", value: known.name)
                if model.state == .idle && model.autoConnect {
                    Button("Automatik fortsetzen") { model.resumeAutoConnect() }
                }
                Button("Scooter vergessen", role: .destructive) { model.forgetScooter() }
            }
            ValueRow(title: "Standort", value: model.locationStatusText)
            if let title = model.locationButtonTitle {
                Button(title) { model.requestLocationAccess() }
            }
        } header: {
            Text("Automatik & Fahrtenbuch")
        } footer: {
            Text("Nach der ersten Verbindung merkt sich die App deinen Scooter und verbindet sich beim Einschalten von selbst — auch im Hintergrund. Solange er verbunden ist, wird die Fahrt aufgezeichnet. Für die Aufzeichnung im Hintergrund braucht die App den Standort „Immer“. Alle Daten bleiben auf deinem iPhone.")
        }
    }
}

struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

enum Format {
    static func kilometers(_ km: Double) -> String {
        String(format: "%.1f km", locale: Locale.current, km)
    }

    static func speed(_ kmh: Double) -> String {
        String(format: "%.0f km/h", locale: Locale.current, kmh)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60
            ? String(format: "%d h %02d min", minutes / 60, minutes % 60)
            : "\(minutes) min"
    }
}

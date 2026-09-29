//
//  ScooterView.swift
//  Hauptbildschirm: Scooter suchen, verbinden, Werte anzeigen, Tempolimit setzen.
//

import SwiftUI

struct ScooterView: View {
    @StateObject private var model = ScooterViewModel()

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
                    valuesSection
                    speedLimitSection
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
            }
            .navigationTitle(model.connectedName ?? "Ninebot")
        }
    }

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

    private var valuesSection: some View {
        Section {
            ForEach(model.values) { value in
                HStack {
                    Text(value.title)
                    Spacer()
                    Text(value.text).foregroundColor(.secondary)
                }
            }
            Button(model.isReading ? "Liest …" : "Aktualisieren") { model.refresh() }
                .disabled(model.isReading)
        } header: {
            Text("Werte")
        }
    }

    private var speedLimitSection: some View {
        Section {
            HStack {
                Text("\(Int(model.speedLimit)) km/h")
                    .monospacedDigit()
                    .frame(width: 70, alignment: .leading)
                Slider(value: $model.speedLimit, in: ScooterViewModel.speedLimitRange, step: 1)
            }
            Button("Limit setzen") { model.applySpeedLimit() }
                .disabled(model.isReading)
        } header: {
            Text("Tempolimit (Begrenzungsmodus)")
        } footer: {
            Text("Setzt die Höchstgeschwindigkeit für den Begrenzungsmodus (Register 0x74). Das Schreiben ist von der Referenz nicht getestet, nur das Lesen. Der Regler endet bei 20 km/h, dem gesetzlichen Maximum in Deutschland (eKFV).")
        }
    }
}

// MARK: - ViewModel

struct ScooterValue: Identifiable {
    let id: String
    let title: String
    var text: String
}

final class ScooterViewModel: ObservableObject {
    static let speedLimitRange: ClosedRange<Double> = 6...20

    @Published private(set) var state: NinebotSessionState = .idle
    @Published private(set) var scooters: [DiscoveredScooter] = []
    @Published private(set) var isScanning = false
    @Published private(set) var connectedName: String?
    @Published private(set) var values: [ScooterValue] = []
    @Published private(set) var isReading = false
    @Published private(set) var message: String?
    @Published var speedLimit: Double = 20

    private let bleManager: NinebotBLEManager
    private let session: NinebotSession
    private var scanID = 0

    init() {
        bleManager = NinebotBLEManager()
        session = NinebotSession(bleManager: bleManager)
        bleManager.onDiscover = { [weak self] scooter in self?.add(scooter) }
        session.onStateChange = { [weak self] state in self?.handle(state) }
    }

    var isBusy: Bool {
        switch state {
        case .connecting, .initializing, .waitingForButtonPress, .pairing: return true
        default: return isScanning || isReading
        }
    }

    var statusText: String {
        switch state {
        case .idle: return isScanning ? "Suche Scooter …" : "Nicht verbunden"
        case .connecting: return "Verbinde …"
        case .initializing: return "Handshake …"
        case .waitingForButtonPress: return "Jetzt den Power-Knopf am Scooter kurz drücken!"
        case .pairing: return "Kopple …"
        case .authenticated: return "Verbunden"
        case .failed(let reason): return "Fehlgeschlagen: \(reason)"
        }
    }

    // MARK: - Suchen und Verbinden

    func startScan() {
        scooters = []
        message = nil
        isScanning = true
        scanID += 1
        let id = scanID
        bleManager.startScanning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.scanID == id, self.isScanning else { return }
            self.stopScan()
        }
    }

    private func stopScan() {
        isScanning = false
        bleManager.stopScanning()
    }

    private func add(_ scooter: DiscoveredScooter) {
        if let i = scooters.firstIndex(where: { $0.id == scooter.id }) {
            scooters[i].rssi = scooter.rssi
        } else {
            scooters.append(scooter)
        }
    }

    func connect(to scooter: DiscoveredScooter) {
        stopScan()
        message = nil
        connectedName = scooter.name
        session.connect(to: scooter)
    }

    func disconnect() {
        session.disconnect()
    }

    private func handle(_ newState: NinebotSessionState) {
        state = newState
        switch newState {
        case .authenticated:
            refresh()
        case .idle, .failed:
            isScanning = false
            isReading = false
            connectedName = nil
            values = []
        default:
            break
        }
    }

    // MARK: - Werte

    func refresh() {
        guard state == .authenticated, !isReading else { return }
        isReading = true
        values = NinebotRegister.overview.map { ScooterValue(id: $0.id, title: $0.title, text: "…") }
        readValue(at: 0)
    }

    private func readValue(at i: Int) {
        let registers = NinebotRegister.overview
        guard i < registers.count, state == .authenticated else {
            isReading = false
            return
        }
        let register = registers[i]
        session.read(register) { [weak self] result in
            guard let self = self else { return }
            self.show(result, for: register)
            self.readValue(at: i + 1)
        }
    }

    private func show(_ result: Result<[UInt8], Error>, for register: NinebotRegister) {
        guard let i = values.firstIndex(where: { $0.id == register.id }) else { return }
        switch result {
        case .success(let data):
            values[i].text = register.format(data)
            if register.device == .controller && register.index == NinebotRegister.speedLimitRegister {
                let kmh = (Double(NinebotValue.les16(data)) / 10).rounded()
                if Self.speedLimitRange.contains(kmh) { speedLimit = kmh }
            }
        case .failure:
            values[i].text = "–"
        }
    }

    // MARK: - Tempolimit

    func applySpeedLimit() {
        let kmh = min(max(speedLimit, Self.speedLimitRange.lowerBound), Self.speedLimitRange.upperBound)
        message = nil
        session.writeRegister(NinebotRegister.speedLimitRegister, value: Int16(kmh * 10)) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.message = "Tempolimit auf \(Int(kmh)) km/h gesetzt"
                self.rereadSpeedLimit()
            case .failure(let error):
                self.message = "Fehler beim Schreiben: \(error.localizedDescription)"
            }
        }
    }

    private func rereadSpeedLimit() {
        guard let register = NinebotRegister.overview.first(where: {
            $0.device == .controller && $0.index == NinebotRegister.speedLimitRegister
        }) else { return }
        session.read(register) { [weak self] result in
            self?.show(result, for: register)
        }
    }
}

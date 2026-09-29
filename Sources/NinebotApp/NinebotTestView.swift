//
//  NinebotTestView.swift
//  Minimaler Testbildschirm, um den Handshake und das Geschwindigkeitsregister auszuprobieren.
//  Ersetze "E2 Pro 0923" durch den Namen, den dein Scooter per Bluetooth anzeigt.
//

import SwiftUI

struct NinebotTestView: View {
    @StateObject private var viewModel = NinebotTestViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("Status: \(viewModel.statusText)")
                .padding()

            Button("Verbinden") {
                viewModel.pair()
            }
            .disabled(viewModel.isBusy)

            Button("Geschwindigkeitsregister lesen") {
                viewModel.readSpeedRegister()
            }
            .disabled(!viewModel.isAuthenticated)

            if let lastRead = viewModel.lastReadValue {
                Text("Gelesener Wert: \(lastRead)")
            }

            HStack {
                Text("Neues Limit: \(Int(viewModel.speedLimit)) km/h")
                Slider(value: $viewModel.speedLimit, in: 5...25, step: 1)
            }
            .padding(.horizontal)

            Button("Sport-Modus-Limit setzen") {
                viewModel.applySpeedLimit()
            }
            .disabled(!viewModel.isAuthenticated)
        }
        .padding()
    }
}

final class NinebotTestViewModel: ObservableObject {
    @Published var statusText: String = "Nicht verbunden"
    @Published var isBusy: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var lastReadValue: String?
    @Published var speedLimit: Double = 20

    private let bleManager = NinebotBLEManager()
    private var session: NinebotSession?

    func pair() {
        isBusy = true
        statusText = "Verbinde..."

        let session = NinebotSession(bleManager: bleManager, deviceName: "E2 Pro 0923")
        session.onStateChange = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch state {
                case .idle: self.statusText = "Nicht verbunden"
                case .connecting: self.statusText = "Verbinde..."
                case .preComm: self.statusText = "Handshake: PRE_COMM..."
                case .settingPassword: self.statusText = "Handshake: Passwort festlegen..."
                case .waitingForButtonPress: self.statusText = "Jetzt den Knopf am Scooter drücken!"
                case .authenticating: self.statusText = "Handshake: Authentifizierung..."
                case .authenticated:
                    self.statusText = "Verbunden und authentifiziert"
                    self.isAuthenticated = true
                    self.isBusy = false
                case .failed(let reason):
                    self.statusText = "Fehlgeschlagen: \(reason)"
                    self.isBusy = false
                }
            }
        }
        self.session = session
        session.pair()
    }

    func readSpeedRegister() {
        session?.readRegister(0x74) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let bytes):
                    self?.lastReadValue = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                case .failure(let error):
                    self?.lastReadValue = "Fehler: \(error)"
                }
            }
        }
    }

    func applySpeedLimit() {
        session?.setSportModeSpeedLimit(kmh: speedLimit) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.statusText = "Geschwindigkeitslimit gesendet"
                case .failure(let error):
                    self?.statusText = "Fehler beim Senden: \(error)"
                }
            }
        }
    }
}

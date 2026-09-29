//
//  NinebotSession.swift
//  Verbindet sich mit dem Scooter, führt den Auth-Handshake durch
//  (INIT → PING → PAIR) und bietet danach verschlüsseltes Lesen/Schreiben von Registern.
//
//  Ablauf wie in ninebot-ble (https://github.com/ownbee/ninebot-ble), das an der
//  F-Serie getestet ist:
//  1. INIT: Scooter liefert seinen BLE-Schlüssel und die Seriennummer.
//  2. PING mit zufälligem App-Schlüssel. Antwort-Index 0 = noch nicht gekoppelt:
//     dann den POWER-Knopf am Scooter drücken, bis er bestätigt.
//  3. PAIR mit der Seriennummer → verbunden.
//
//  Nur mit dem eigenen Fahrzeug verwenden — der Handshake erfordert ohnehin den
//  physischen Knopf am Scooter.
//

import Foundation
import CoreBluetooth
import Security

enum NinebotSessionState: Equatable {
    case idle
    case connecting
    case initializing
    case waitingForButtonPress
    case pairing
    case authenticated
    case failed(String)
}

enum NinebotSessionError: LocalizedError {
    case notAuthenticated
    case timeout
    case invalidResponse
    case disconnected

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Nicht verbunden"
        case .timeout: return "Keine Antwort vom Scooter"
        case .invalidResponse: return "Ungültige Antwort vom Scooter"
        case .disconnected: return "Verbindung getrennt"
        }
    }
}

final class NinebotSession {

    private let bleManager: NinebotBLEManager
    private var crypto: NinebotCrypto?

    private let appKey: [UInt8] = NinebotSession.randomBytes(16)
    private var serialNumber: [UInt8] = []

    /// Wie lange auf den Knopfdruck am Scooter gewartet wird.
    private let buttonPressTimeout: TimeInterval = 60
    private var buttonTimer: Timer?
    private var buttonDeadline = Date()
    private var userDisconnect = false

    // Anfragen werden nacheinander abgearbeitet; jede wird bis zum Timeout
    // jede Sekunde neu gesendet (wie NinebotClient.request in ninebot-ble).
    private struct Request {
        let packet: NinebotPacket
        let timeout: TimeInterval
        let completion: (Result<NinebotPacket, Error>) -> Void
    }
    private var queue: [Request] = []
    private var current: Request?
    private var currentDeadline = Date()
    private var retryTimer: Timer?

    var onStateChange: ((NinebotSessionState) -> Void)?
    private(set) var state: NinebotSessionState = .idle {
        didSet { onStateChange?(state) }
    }

    init(bleManager: NinebotBLEManager) {
        self.bleManager = bleManager
        bleManager.onReady = { [weak self] in self?.startInit() }
        bleManager.onFrame = { [weak self] frame in self?.handleFrame(frame) }
        bleManager.onDisconnect = { [weak self] error in self?.handleDisconnect(error) }
        bleManager.onError = { [weak self] error in self?.fail(error.localizedDescription) }
    }

    // MARK: - Öffentlicher Ablauf

    /// Verbindet mit dem gewählten Scooter. `name` muss der Name sein, den er
    /// bewirbt — er geht in den Schlüssel ein.
    func connect(to scooter: DiscoveredScooter) {
        userDisconnect = false
        state = .connecting
        reset()
        crypto = NinebotCrypto(name: Array(scooter.name.utf8))
        bleManager.connect(to: scooter.peripheral)
    }

    func disconnect() {
        userDisconnect = true
        state = .idle
        reset()
        bleManager.disconnect()
    }

    /// Liest ein Register (bzw. mehrere aufeinanderfolgende) und liefert die Rohbytes.
    func read(_ register: NinebotRegister, completion: @escaping (Result<[UInt8], Error>) -> Void) {
        readRange(device: register.device, from: register.index, count: register.count,
                  collected: [], completion: completion)
    }

    /// Schreibt 2 Bytes (Little-Endian) in ein Register der Hauptsteuerung.
    func writeRegister(_ index: UInt8, value: Int16, completion: @escaping (Result<Void, Error>) -> Void) {
        guard state == .authenticated else {
            completion(.failure(NinebotSessionError.notAuthenticated))
            return
        }
        let raw = UInt16(bitPattern: value)
        let packet = NinebotPacket(target: .controller, command: .write, index: index,
                                   data: [UInt8(raw & 0xFF), UInt8(raw >> 8)])
        request(packet) { result in
            completion(result.map { _ in () })
        }
    }

    // MARK: - Handshake

    private func startInit() {
        guard state == .connecting else { return }
        state = .initializing
        request(NinebotPacket(target: .ble, command: .initialize)) { [weak self] result in
            guard let self = self, self.state == .initializing else { return }
            guard case .success(let response) = result, response.data.count >= 16 else {
                self.fail("Handshake (INIT): \(self.describe(result))")
                return
            }
            self.serialNumber = Array(response.data.dropFirst(16))
            self.crypto?.setBleData(Array(response.data.prefix(16)))
            self.sendPing()
        }
    }

    private func sendPing() {
        request(NinebotPacket(target: .ble, command: .ping, data: appKey)) { [weak self] result in
            guard let self = self, self.state == .initializing else { return }
            guard case .success(let response) = result else {
                self.fail("Handshake (PING): \(self.describe(result))")
                return
            }
            if response.index == 0 {
                self.waitForButtonPress()
            } else {
                // Schon gekoppelt. ninebot-ble behält hier den bisherigen Schlüssel;
                // klappt PAIR damit nicht, versucht startPair es mit dem App-Schlüssel.
                self.startPair(alternateKeyOnTimeout: true)
            }
        }
    }

    /// Sendet jede Sekunde PAIR, bis der Scooter den Knopfdruck bestätigt.
    private func waitForButtonPress() {
        state = .waitingForButtonPress
        buttonDeadline = Date().addingTimeInterval(buttonPressTimeout)
        buttonTimer?.invalidate()
        buttonTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if Date() > self.buttonDeadline {
                self.fail("Kein Knopfdruck am Scooter innerhalb von \(Int(self.buttonPressTimeout)) s")
                return
            }
            self.send(NinebotPacket(target: .ble, command: .pair, data: self.serialNumber))
        }
    }

    private func handleButtonPressResponse(_ packet: NinebotPacket) {
        guard packet.source == NinebotDevice.ble.rawValue, packet.index == 1 else { return }
        if packet.command == NinebotCommand.ping.rawValue {
            buttonTimer?.invalidate()
            crypto?.setAppData(appKey)
            startPair(alternateKeyOnTimeout: false)
        } else if packet.command == NinebotCommand.pair.rawValue {
            buttonTimer?.invalidate()
            startPair(alternateKeyOnTimeout: false)
        }
    }

    private func startPair(alternateKeyOnTimeout: Bool) {
        state = .pairing
        request(NinebotPacket(target: .ble, command: .pair, data: serialNumber)) { [weak self] result in
            guard let self = self, self.state == .pairing else { return }
            switch result {
            case .success:
                self.state = .authenticated
            case .failure(NinebotSessionError.timeout) where alternateKeyOnTimeout:
                self.crypto?.setAppData(self.appKey)
                self.startPair(alternateKeyOnTimeout: false)
            case .failure:
                self.fail("Handshake (PAIR): \(self.describe(result))")
            }
        }
    }

    // MARK: - Register lesen

    private func readRange(device: NinebotDevice, from index: UInt8, count: Int, collected: [UInt8],
                           completion: @escaping (Result<[UInt8], Error>) -> Void) {
        guard state == .authenticated else {
            completion(.failure(NinebotSessionError.notAuthenticated))
            return
        }
        guard count > 0 else {
            completion(.success(collected))
            return
        }
        // Wie in ninebot-ble: pro Register 2 Bytes anfordern.
        let packet = NinebotPacket(target: device, command: .read, index: index, data: [2])
        request(packet) { [weak self] result in
            switch result {
            case .success(let response):
                self?.readRange(device: device, from: index &+ 1, count: count - 1,
                                collected: collected + response.data, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Senden / Empfangen

    private func send(_ packet: NinebotPacket) {
        guard let crypto = crypto else { return }
        bleManager.send(crypto.encrypt(packet.pack()))
    }

    private func request(_ packet: NinebotPacket, timeout: TimeInterval = 5,
                         completion: @escaping (Result<NinebotPacket, Error>) -> Void) {
        queue.append(Request(packet: packet, timeout: timeout, completion: completion))
        startNextRequest()
    }

    private func startNextRequest() {
        guard current == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        current = next
        currentDeadline = Date().addingTimeInterval(next.timeout)
        send(next.packet)
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let request = self.current else { return }
            if Date() > self.currentDeadline {
                self.finishCurrent(.failure(NinebotSessionError.timeout))
            } else {
                self.send(request.packet)
            }
        }
    }

    private func finishCurrent(_ result: Result<NinebotPacket, Error>) {
        retryTimer?.invalidate()
        retryTimer = nil
        guard let request = current else { return }
        current = nil
        request.completion(result)
        startNextRequest()
    }

    private func handleFrame(_ frame: [UInt8]) {
        guard let plaintext = crypto?.decrypt(frame),
              let packet = NinebotPacket.unpack(plaintext) else { return }   // Unlesbares ignorieren

        if state == .waitingForButtonPress {
            handleButtonPressResponse(packet)
        } else if let request = current, packet.isResponse(to: request.packet) {
            finishCurrent(.success(packet))
        }
        // Alles andere (z. B. späte Antworten auf wiederholte Anfragen) wird ignoriert.
    }

    private func handleDisconnect(_ error: Error?) {
        switch state {
        case .idle, .failed:
            break
        default:
            state = userDisconnect
                ? .idle
                : .failed(error?.localizedDescription ?? NinebotSessionError.disconnected.localizedDescription)
        }
        reset()
    }

    // MARK: - Hilfen

    private func fail(_ reason: String) {
        state = .failed(reason)
        reset()
        bleManager.disconnect()
    }

    /// Stoppt alle Timer und bricht offene Anfragen ab. Vorher `state` setzen:
    /// Die Handshake-Schritte prüfen ihn und ignorieren abgebrochene Anfragen.
    private func reset() {
        buttonTimer?.invalidate()
        buttonTimer = nil
        retryTimer?.invalidate()
        retryTimer = nil
        let pending = (current.map { [$0] } ?? []) + queue
        current = nil
        queue = []
        pending.forEach { $0.completion(.failure(NinebotSessionError.disconnected)) }
    }

    private func describe(_ result: Result<NinebotPacket, Error>) -> String {
        switch result {
        case .success: return NinebotSessionError.invalidResponse.localizedDescription
        case .failure(let error): return error.localizedDescription
        }
    }

    private static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            bytes = (0..<count).map { _ in UInt8.random(in: 0...255) }
        }
        return bytes
    }
}

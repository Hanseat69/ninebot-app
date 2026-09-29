//
//  NinebotBLEManager.swift
//  CoreBluetooth-Anbindung für Segway-Ninebot-Scooter (getestete Referenz: F-Serie).
//
//  Aufgaben:
//  - Scooter in der Nähe finden (Ninebot-Herstellerkennung oder UART-Service in der Werbung)
//  - verbinden und die UART-Characteristics einrichten
//  - Frames in 20-Byte-Stücken senden und empfangene Stücke wieder zu ganzen
//    Frames zusammensetzen
//
//  Die Verschlüsselung passiert eine Ebene höher (NinebotSession / NinebotCrypto).
//
//  Referenzen zum Protokoll (Community-Reverse-Engineering, keine offizielle Segway-Quelle):
//  - https://github.com/ownbee/ninebot-ble   (Python-Client, entwickelt an der F-Serie)
//  - https://github.com/dnandha/miauth       (Handshake und Krypto)
//

import Foundation
import CoreBluetooth

// MARK: - Ninebot UART Service/Characteristic UUIDs
// Diese UUIDs stammen aus Community-Reverse-Engineering des Ninebot-BLE-UART-Service.
enum NinebotBLE {
    static let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let writeCharUUID   = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Telefon -> Scooter
    static let notifyCharUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Scooter -> Telefon

    /// Bluetooth-Herstellerkennung von Ninebot (16974 = 0x424E, in der Werbung "NB").
    static let manufacturerID: UInt16 = 16974

    /// Maximale Nutzlast pro Schreibvorgang bei Standard-MTU; so macht es auch die Referenz.
    static let chunkSize = 20
}

struct DiscoveredScooter: Identifiable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    var rssi: Int
}

enum NinebotBLEError: LocalizedError {
    case bluetoothUnavailable(String)
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable(let reason): return reason
        case .connectionFailed: return "Verbindung zum Scooter fehlgeschlagen"
        }
    }
}

final class NinebotBLEManager: NSObject {

    private var centralManager: CBCentralManager?
    private var scooterPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var receiveBuffer: [UInt8] = []
    private var scanRequested = false
    private var restoredPeripherals: [CBPeripheral] = []

    /// Auf true setzen, um alle BLE-Geräte statt nur Ninebot-Geräte anzuzeigen.
    /// Praktisch bei der ersten Fehlersuche.
    var scanForAllDevices = false

    /// Ein Scooter wurde gefunden (auch erneut, mit aktualisierter Signalstärke).
    var onDiscover: ((DiscoveredScooter) -> Void)?
    /// Verbunden, Notifications aktiv, Schreiben möglich.
    var onReady: (() -> Void)?
    /// Ein vollständiger (noch verschlüsselter) Frame ist angekommen.
    var onFrame: (([UInt8]) -> Void)?
    /// Verbindung getrennt (error == nil, wenn wir selbst getrennt haben).
    var onDisconnect: ((Error?) -> Void)?
    /// Bluetooth aus/nicht erlaubt oder Verbindungsaufbau gescheitert.
    var onError: ((Error) -> Void)?
    /// Bluetooth ist (wieder) eingeschaltet und bereit.
    var onPoweredOn: (() -> Void)?

    override init() {
        super.init()
        // Mit Restore-Kennung startet iOS die App im Hintergrund neu, wenn sich der
        // gemerkte Scooter meldet, selbst wenn die App zwischendurch beendet wurde.
        guard !DemoMode.isActive else { return }   // Screenshots: kein Bluetooth
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: "NinebotCentral"
        ])
    }

    var isPoweredOn: Bool { centralManager?.state == .poweredOn }

    /// Findet einen früher verbundenen Scooter wieder, ohne zu suchen.
    func peripheral(withIdentifier id: UUID) -> CBPeripheral? {
        if let restored = restoredPeripherals.first(where: { $0.identifier == id }) {
            return restored
        }
        guard isPoweredOn else { return nil }
        return centralManager?.retrievePeripherals(withIdentifiers: [id]).first
    }

    // MARK: - Öffentliche API

    /// Startet die Suche. Ist Bluetooth noch nicht bereit, beginnt sie, sobald es das ist.
    func startScanning() {
        scanRequested = true
        guard let centralManager = centralManager, centralManager.state == .poweredOn else {
            if let state = centralManager?.state, let problem = bluetoothProblem(state) {
                scanRequested = false
                onError?(NinebotBLEError.bluetoothUnavailable(problem))
            }
            return
        }
        // Keine Service-Filterung: nicht jede Firmware bewirbt den UART-Service.
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
    }

    func stopScanning() {
        scanRequested = false
        if centralManager?.state == .poweredOn {
            centralManager?.stopScan()
        }
    }

    /// Verbindet mit dem Scooter. Ist er gerade aus, bleibt der Auftrag bestehen
    /// und iOS verbindet, sobald er eingeschaltet wird (auch im Hintergrund).
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        if let previous = scooterPeripheral, previous.identifier != peripheral.identifier {
            centralManager?.cancelPeripheralConnection(previous)
        }
        resetConnectionState()
        scooterPeripheral = peripheral
        peripheral.delegate = self
        if peripheral.state == .connected {
            peripheral.discoverServices([NinebotBLE.uartServiceUUID])
        } else {
            centralManager?.connect(peripheral, options: nil)
        }
    }

    func disconnect() {
        guard let peripheral = scooterPeripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    /// Sendet einen fertig verschlüsselten Frame, aufgeteilt in 20-Byte-Stücke.
    func send(_ frame: [UInt8]) {
        guard let peripheral = scooterPeripheral,
              let characteristic = writeCharacteristic else {
            print("Noch nicht verbunden oder Write-Characteristic nicht gefunden")
            return
        }
        // Mit Antwort, wenn möglich: CoreBluetooth stellt die Stücke dann zuverlässig
        // in der richtigen Reihenfolge zu.
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write)
            ? .withResponse : .withoutResponse
        var offset = 0
        while offset < frame.count {
            let end = min(offset + NinebotBLE.chunkSize, frame.count)
            peripheral.writeValue(Data(frame[offset..<end]), for: characteristic, type: type)
            offset = end
        }
    }

    // MARK: - Hilfen

    private func resetConnectionState() {
        writeCharacteristic = nil
        notifyCharacteristic = nil
        receiveBuffer = []
    }

    private func bluetoothProblem(_ state: CBManagerState) -> String? {
        switch state {
        case .poweredOff: return "Bluetooth ist aus — bitte in den Einstellungen einschalten"
        case .unauthorized: return "App hat keine Bluetooth-Berechtigung"
        case .unsupported: return "Dieses Gerät unterstützt kein Bluetooth LE"
        default: return nil   // .unknown / .resetting: gleich wieder da
        }
    }

    private func isNinebot(_ advertisementData: [String: Any]) -> Bool {
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data.count >= 2 {
            let bytes = [UInt8](data)
            let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            if company == NinebotBLE.manufacturerID { return true }
        }
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        return services.contains(NinebotBLE.uartServiceUUID)
    }

    /// Setzt eingehende Stücke zu ganzen Frames zusammen.
    /// Frame = 3 Byte Header + 4 Byte (SRC/DST/CMD/INDEX) + LEN Byte Daten + 6 Byte Tag/Zähler
    private func receive(_ chunk: [UInt8]) {
        if chunk.count >= 2 && chunk[0] == 0x5A && chunk[1] == 0xA5 {
            receiveBuffer = chunk
        } else if !receiveBuffer.isEmpty {
            receiveBuffer += chunk
        } else {
            return   // Bruchstück ohne Anfang: verwerfen
        }

        guard receiveBuffer.count >= 3 else { return }
        let total = Int(receiveBuffer[2]) + 13
        if receiveBuffer.count >= total {
            let frame = Array(receiveBuffer.prefix(total))
            receiveBuffer = []
            onFrame?(frame)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension NinebotBLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            if scanRequested { startScanning() }
            onPoweredOn?()
        } else if let problem = bluetoothProblem(central.state) {
            onError?(NinebotBLEError.bluetoothUnavailable(problem))
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        restoredPeripherals.forEach { $0.delegate = self }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard scanForAllDevices || isNinebot(advertisementData) else { return }
        // Der beworbene Name ist zuverlässiger als peripheral.name (der kann zwischengespeichert sein).
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name
        guard let name = advertisedName, !name.isEmpty else { return }
        onDiscover?(DiscoveredScooter(id: peripheral.identifier, peripheral: peripheral,
                                      name: name, rssi: RSSI.intValue))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([NinebotBLE.uartServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        guard peripheral.identifier == scooterPeripheral?.identifier else { return }
        scooterPeripheral = nil
        onError?(error ?? NinebotBLEError.connectionFailed)
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        guard peripheral.identifier == scooterPeripheral?.identifier else { return }   // alte Verbindung
        scooterPeripheral = nil
        resetConnectionState()
        onDisconnect?(error)
    }
}

// MARK: - CBPeripheralDelegate

extension NinebotBLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            onError?(error)
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == NinebotBLE.uartServiceUUID }) else {
            onError?(NinebotBLEError.bluetoothUnavailable("UART-Service nicht gefunden — ist das ein Ninebot?"))
            disconnect()
            return
        }
        peripheral.discoverCharacteristics([NinebotBLE.writeCharUUID, NinebotBLE.notifyCharUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error {
            onError?(error)
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case NinebotBLE.writeCharUUID:
                writeCharacteristic = characteristic
            case NinebotBLE.notifyCharUUID:
                notifyCharacteristic = characteristic
            default:
                break
            }
        }
        guard writeCharacteristic != nil, let notify = notifyCharacteristic else {
            onError?(NinebotBLEError.bluetoothUnavailable("UART-Characteristics nicht gefunden"))
            disconnect()
            return
        }
        // Bereit sind wir erst, wenn der Scooter die Notifications bestätigt hat.
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            onError?(error)
            return
        }
        if characteristic.uuid == NinebotBLE.notifyCharUUID && characteristic.isNotifying {
            onReady?()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil,
              characteristic.uuid == NinebotBLE.notifyCharUUID,
              let data = characteristic.value else { return }
        receive([UInt8](data))
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            print("Schreiben fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}

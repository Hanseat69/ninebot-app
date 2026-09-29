//
//  NinebotBLEManager.swift
//  Grundlegender CoreBluetooth-Connector für Segway-Ninebot-Scooter (u. a. E2 Pro)
//
//  WICHTIG:
//  - Dies übernimmt Scannen, Verbinden und das Erkennen des UART-Service und der Characteristics.
//  - Neuere Ninebot-Modelle (inkl. E2 Pro) nutzen ein verschlüsseltes Protokoll
//    ("miauth"). Ohne diese Verschlüsselungsschicht bekommst du KEINE lesbare Telemetrie,
//    nur einen rohen (verschlüsselten) Bytestrom. Siehe Community-Referenzen unten.
//  - Im Xcode-Projekt in der Info.plist ergänzen:
//      NSBluetoothAlwaysUsageDescription
//      (Text, z. B. "Wird benötigt, um per Bluetooth mit deinem Scooter zu verbinden")
//
//  Referenzen zum Protokoll (Community-Reverse-Engineering, keine offizielle Segway-Quelle):
//  - https://github.com/ownbee/ninebot-ble   (Python-Client inkl. miauth-Krypto)
//  - https://codeberg.org/NootNooot/segway-ninebot-ble-cli
//  - https://github.com/CamiAlfa/M365-BLE-PROTOCOL
//

import Foundation
import CoreBluetooth

// MARK: - Ninebot UART Service/Characteristic UUIDs
// Diese UUIDs stammen aus Community-Reverse-Engineering des Ninebot-BLE-UART-Service.
enum NinebotBLE {
    static let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let writeCharUUID   = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Telefon -> Scooter
    static let notifyCharUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Scooter -> Telefon
}

protocol NinebotBLEManagerDelegate: AnyObject {
    func ninebotManager(_ manager: NinebotBLEManager, didDiscover peripheral: CBPeripheral, rssi: NSNumber)
    func ninebotManager(_ manager: NinebotBLEManager, didConnect peripheral: CBPeripheral)
    func ninebotManager(_ manager: NinebotBLEManager, didDisconnect peripheral: CBPeripheral, error: Error?)
    func ninebotManager(_ manager: NinebotBLEManager, didReceiveRawData data: Data)
    func ninebotManager(_ manager: NinebotBLEManager, didFailWithError error: Error)
}

final class NinebotBLEManager: NSObject {

    weak var delegate: NinebotBLEManagerDelegate?

    private var centralManager: CBCentralManager!
    private var scooterPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    /// Auf true setzen, um alle BLE-Geräte statt nur Geräte mit dem Ninebot-UART-Service anzuzeigen.
    /// Praktisch bei der ersten Fehlersuche (manche Firmwares bewerben den Service nicht immer).
    var scanForAllDevices = false

    /// Wird ausgelöst, sobald sowohl die Write- als auch die Notify-Characteristic gefunden sind —
    /// erst dann ist sendRaw() sinnvoll. Nutze dies, statt nach didConnect mit einer festen
    /// Verzögerung zu raten (Discovery ist asynchron, ihre Dauer ist nicht garantiert).
    var onCharacteristicsReady: (() -> Void)?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Öffentliche API

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            print("Bluetooth ist nicht an oder nicht verfügbar (State: \(centralManager.state.rawValue))")
            return
        }
        let services = scanForAllDevices ? nil : [NinebotBLE.uartServiceUUID]
        centralManager.scanForPeripherals(withServices: services, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        scooterPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = scooterPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    /// Sendet rohe Bytes an den Scooter. Für echte Befehle muss dies ein korrekt
    /// aufgebauter Ninebot-Protokollframe sein (Header, Prüfsumme, ggf. Verschlüsselung).
    func sendRaw(_ data: Data) {
        guard let peripheral = scooterPeripheral,
              let characteristic = writeCharacteristic else {
            print("Noch nicht verbunden oder Write-Characteristic nicht gefunden")
            return
        }
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: characteristic, type: type)
    }
}

// MARK: - CBCentralManagerDelegate

extension NinebotBLEManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth ist an")
        case .poweredOff:
            print("Bluetooth ist aus — bitte in den Einstellungen einschalten")
        case .unauthorized:
            print("App hat keine Bluetooth-Berechtigung")
        default:
            print("Bluetooth state: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any],
                         rssi RSSI: NSNumber) {
        delegate?.ninebotManager(self, didDiscover: peripheral, rssi: RSSI)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([NinebotBLE.uartServiceUUID])
        delegate?.ninebotManager(self, didConnect: peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                         didFailToConnect peripheral: CBPeripheral,
                         error: Error?) {
        if let error = error {
            delegate?.ninebotManager(self, didFailWithError: error)
        }
    }

    func centralManager(_ central: CBCentralManager,
                         didDisconnectPeripheral peripheral: CBPeripheral,
                         error: Error?) {
        delegate?.ninebotManager(self, didDisconnect: peripheral, error: error)
    }
}

// MARK: - CBPeripheralDelegate

extension NinebotBLEManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            delegate?.ninebotManager(self, didFailWithError: error)
            return
        }
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == NinebotBLE.uartServiceUUID {
            peripheral.discoverCharacteristics(
                [NinebotBLE.writeCharUUID, NinebotBLE.notifyCharUUID],
                for: service
            )
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didDiscoverCharacteristicsFor service: CBService,
                     error: Error?) {
        if let error = error {
            delegate?.ninebotManager(self, didFailWithError: error)
            return
        }
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case NinebotBLE.writeCharUUID:
                writeCharacteristic = characteristic
            case NinebotBLE.notifyCharUUID:
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }
        if writeCharacteristic != nil && notifyCharacteristic != nil {
            onCharacteristicsReady?()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didUpdateValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        if let error = error {
            delegate?.ninebotManager(self, didFailWithError: error)
            return
        }
        guard characteristic.uuid == NinebotBLE.notifyCharUUID,
              let data = characteristic.value else { return }
        // Rohe (evtl. verschlüsselte) Bytes vom Scooter — Dekodierung/Entschlüsselung ist
        // hier noch nicht implementiert, siehe Hinweis oben in der Datei.
        delegate?.ninebotManager(self, didReceiveRawData: data)
    }

    func peripheral(_ peripheral: CBPeripheral,
                     didWriteValueFor characteristic: CBCharacteristic,
                     error: Error?) {
        if let error = error {
            delegate?.ninebotManager(self, didFailWithError: error)
        }
    }
}

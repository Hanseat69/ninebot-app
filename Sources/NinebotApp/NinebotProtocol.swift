//
//  NinebotProtocol.swift
//  Paketformat und Registertabelle des Ninebot-BLE-Protokolls (5A A5 …).
//
//  Adressen, Befehle und Register stammen aus ninebot-ble
//  (https://github.com/ownbee/ninebot-ble), das an einem Ninebot der F-Serie
//  entwickelt und getestet wurde — also derselben Familie wie der F2 Pro.
//

import Foundation

// MARK: - Adressen und Befehle

enum NinebotDevice: UInt8 {
    case controller = 0x20   // Hauptsteuerung (ES_CONTROL)
    case ble        = 0x21   // Bluetooth-Modul (ES_BLE)
    case battery    = 0x22   // Akku / BMS (ES_BATT)
    case app        = 0x3D   // Absender, den miauth und ninebot-ble verwenden
}

enum NinebotCommand: UInt8 {
    case read       = 0x01   // Register lesen
    case write      = 0x02   // Register schreiben, mit Antwort
    case readAck    = 0x04   // Antwort auf read
    case writeAck   = 0x05   // Antwort auf write
    case initialize = 0x5B   // Handshake 1: BLE-Schlüssel + Seriennummer holen
    case ping       = 0x5C   // Handshake 2: App-Schlüssel senden
    case pair       = 0x5D   // Handshake 3: Koppeln mit Seriennummer
}

// MARK: - Paket

/// Unverschlüsseltes Paket: 5A A5 LEN SRC DST CMD INDEX DATA…
/// LEN ist die Länge von DATA.
struct NinebotPacket {
    let source: UInt8
    let target: UInt8
    let command: UInt8
    let index: UInt8
    let data: [UInt8]

    init(source: NinebotDevice = .app, target: NinebotDevice, command: NinebotCommand,
         index: UInt8 = 0, data: [UInt8] = []) {
        self.source = source.rawValue
        self.target = target.rawValue
        self.command = command.rawValue
        self.index = index
        self.data = data
    }

    private init(source: UInt8, target: UInt8, command: UInt8, index: UInt8, data: [UInt8]) {
        self.source = source
        self.target = target
        self.command = command
        self.index = index
        self.data = data
    }

    func pack() -> [UInt8] {
        [0x5A, 0xA5, UInt8(data.count & 0xFF), source, target, command, index] + data
    }

    static func unpack(_ bytes: [UInt8]) -> NinebotPacket? {
        guard bytes.count >= 7, bytes[0] == 0x5A, bytes[1] == 0xA5 else { return nil }
        let length = Int(bytes[2])
        guard bytes.count >= 7 + length else { return nil }
        return NinebotPacket(source: bytes[3], target: bytes[4], command: bytes[5], index: bytes[6],
                             data: Array(bytes[7..<(7 + length)]))
    }

    /// Prüft, ob `self` die Antwort auf `request` ist (wie NinebotClient.request in ninebot-ble).
    func isResponse(to request: NinebotPacket) -> Bool {
        let expectedCommand: UInt8
        switch NinebotCommand(rawValue: request.command) {
        case .read: expectedCommand = NinebotCommand.readAck.rawValue
        case .write: expectedCommand = NinebotCommand.writeAck.rawValue
        default: expectedCommand = request.command
        }
        return source == request.target
            && target == request.source
            && command == expectedCommand
            && (request.command > 0x05 || index == request.index)
    }
}

// MARK: - Register

/// Ein lesbarer Wert. Jedes Register ist 2 Bytes breit; manche Werte belegen
/// mehrere aufeinanderfolgende Register (`count`).
struct NinebotRegister: Identifiable {
    let id: String
    let title: String
    let device: NinebotDevice
    let index: UInt8
    let count: Int
    let format: ([UInt8]) -> String

    init(_ title: String, _ device: NinebotDevice, _ index: UInt8, count: Int = 1,
         format: @escaping ([UInt8]) -> String) {
        self.id = "\(device.rawValue)-\(index)-\(title)"
        self.title = title
        self.device = device
        self.index = index
        self.count = count
        self.format = format
    }
}

enum NinebotValue {
    static func le16(_ d: [UInt8]) -> Int {
        d.count >= 2 ? Int(d[0]) | (Int(d[1]) << 8) : 0
    }

    static func les16(_ d: [UInt8]) -> Int {
        Int(Int16(truncatingIfNeeded: le16(d)))
    }

    static func u32(_ d: [UInt8]) -> Int {
        le16(Array(d.prefix(2))) + (le16(Array(d.dropFirst(2))) << 16)
    }

    static func text(_ d: [UInt8]) -> String {
        String(decoding: d.filter { $0 != 0 }, as: UTF8.self)
    }

    static func version(_ d: [UInt8]) -> String {
        let v = le16(d)
        return "\(v >> 8).\((v >> 4) & 0x0F).\(v & 0x0F)"
    }

    /// Gesamtkilometer: 32 Bit aus zwei Registern, Einheit Meter.
    static func kilometers(_ d: [UInt8]) -> Double {
        Double(u32(d)) / 1000
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return s >= 3600
            ? String(format: "%d:%02d:%02d h", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d min", s / 60, s % 60)
    }

    static func decimal(_ value: Double, _ digits: Int, _ unit: String) -> String {
        String(format: "%.\(digits)f %@", locale: Locale.current, value, unit)
    }
}

extension NinebotRegister {
    // Alle Register und Einheiten wie in ninebot-ble (F-Serie).

    // MARK: Akku (BMS)
    static let batteryPercent = NinebotRegister("Akku", .battery, 0x32) { "\(NinebotValue.le16($0)) %" }
    static let batteryVoltage = NinebotRegister("Akkuspannung", .battery, 0x34) {
        NinebotValue.decimal(Double(NinebotValue.le16($0)) / 100, 2, "V")
    }
    static let batteryCurrent = NinebotRegister("Akkustrom", .battery, 0x33) {
        NinebotValue.decimal(Double(NinebotValue.les16($0)) / 100, 2, "A")
    }
    static let batteryTemperature = NinebotRegister("Akkutemperatur", .battery, 0x35) {
        "\((NinebotValue.le16($0) & 0xFF) - 20) °C"
    }
    static let batteryHealth = NinebotRegister("Akkuzustand", .battery, 0x3B) { "\(NinebotValue.le16($0)) %" }

    // MARK: Fahrzeug
    static let remainingRange = NinebotRegister("Restreichweite", .controller, 0x25) {
        NinebotValue.decimal(Double(NinebotValue.le16($0)) / 100, 1, "km")
    }
    static let totalMileage = NinebotRegister("Gesamtkilometer", .controller, 0x29, count: 2) {
        NinebotValue.decimal(NinebotValue.kilometers($0), 1, "km")
    }
    static let tripDistance = NinebotRegister("Strecke seit Einschalten", .controller, 0xB9) {
        NinebotValue.decimal(Double(NinebotValue.le16($0)) / 100, 2, "km")
    }
    static let tripTime = NinebotRegister("Zeit seit Einschalten", .controller, 0xBA) {
        NinebotValue.duration(TimeInterval(NinebotValue.le16($0)))
    }
    static let bodyTemperature = NinebotRegister("Fahrzeugtemperatur", .controller, 0x3E) {
        NinebotValue.decimal(Double(NinebotValue.le16($0)) / 10, 1, "°C")
    }
    static let workMode = NinebotRegister("Fahrmodus", .controller, 0x75) {
        switch NinebotValue.le16($0) {
        case 0: return "Normal"
        case 1: return "Eco"
        case 2: return "Sport"
        case let other: return "Unbekannt (\(other))"
        }
    }
    static let normalSpeedLimit = NinebotRegister("Tempolimit normal", .controller, 0x73) {
        NinebotValue.decimal(Double(NinebotValue.les16($0)) / 10, 1, "km/h")
    }
    /// NB_CTL_LITSPEED: Tempolimit im Begrenzungsmodus, Einheit 0,1 km/h.
    static let speedLimit = NinebotRegister("Tempolimit Begrenzungsmodus", .controller, 0x74) {
        NinebotValue.decimal(Double(NinebotValue.les16($0)) / 10, 1, "km/h")
    }
    static let locked = NinebotRegister("Gesperrt", .controller, 0x1D) {
        NinebotValue.le16($0) & 0x02 != 0 ? "Ja" : "Nein"
    }
    static let errorCode = NinebotRegister("Fehlercode", .controller, 0x1B) {
        ScooterErrorCode.describe(NinebotValue.le16($0))
    }
    static let firmware = NinebotRegister("Firmware", .controller, 0x1A) { NinebotValue.version($0) }
    static let serialNumber = NinebotRegister("Seriennummer", .controller, 0x10, count: 7) { NinebotValue.text($0) }

    // MARK: Einstellungen (lesbar laut Referenz; Schreiben ist dort nicht getestet)
    static let kers = NinebotRegister("Rekuperation (KERS)", .controller, 0x7B) {
        switch NinebotValue.le16($0) {
        case 0: return "Aus"
        case 1: return "Mittel"
        case 2: return "Stark"
        case let other: return "Unbekannt (\(other))"
        }
    }
    static let cruiseControl = NinebotRegister("Tempomat", .controller, 0x7C) {
        NinebotValue.le16($0) != 0 ? "An" : "Aus"
    }
    static let tailLight = NinebotRegister("Rücklicht", .controller, 0x7D) {
        NinebotValue.le16($0) != 0 ? "An" : "Aus"
    }

    // MARK: Gruppen für die Anzeige

    /// Wird während der Verbindung alle paar Sekunden gelesen.
    static let live: [NinebotRegister] = [
        batteryPercent, remainingRange, batteryVoltage, batteryCurrent,
        tripDistance, tripTime, totalMileage,
    ]

    /// Wird beim Verbinden und auf Knopfdruck gelesen.
    static let overview: [NinebotRegister] = [
        batteryHealth, batteryTemperature, bodyTemperature, workMode,
        normalSpeedLimit, speedLimit, locked, errorCode, firmware, serialNumber,
    ]

    static let settings: [NinebotRegister] = [kers, cruiseControl, tailLight]
}

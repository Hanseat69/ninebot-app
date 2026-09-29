//
//  NinebotCrypto.swift
//  Implementierung des "Encryption2"-Protokolls, das Segway-Ninebot-Fahrzeuge
//  verwenden: AES-128 in einem eigenen CTR-ähnlichen Modus mit CBC-MAC-Authentifizierung
//  (ähnlich, aber nicht identisch mit NIST CCM).
//
//  1:1-Portierung von NbCrypto aus miauth (https://github.com/dnandha/miauth),
//  das wiederum auf https://github.com/scooterhacking/NinebotCrypto basiert.
//
//  Von der Community per Reverse Engineering der offiziellen App dokumentiert,
//  veröffentlicht zur Interoperabilität gemäß EU-Richtlinie 2009/24/EG Art. 6.
//  Nur zur Verwendung mit dem EIGENEN Fahrzeug.
//

import Foundation
import CryptoKit

final class NinebotCrypto {

    /// Feste Konstante aus der Firmware; Startwert für Schlüssel und Keystream.
    static let fwData: [UInt8] = [0x97, 0xCF, 0xB8, 0x02, 0x84, 0x41, 0x43, 0xDE,
                                  0x56, 0x00, 0x2B, 0x3B, 0x34, 0x78, 0x0A, 0x5D]

    private let name: [UInt8]
    private var bleData: [UInt8]?
    private var sha1Key: [UInt8]

    /// Nachrichtenzähler. Wird aus jeder Antwort des Scooters übernommen und vor
    /// jedem Senden im SN-Modus um 1 erhöht. Solange er 0 ist, wird im
    /// einfachen Modus (fester Keystream + Prüfsumme) verschlüsselt.
    private(set) var counter: UInt32 = 0

    /// - Parameter name: Bluetooth-Name des Scooters, so wie er ihn bewirbt.
    init(name: [UInt8]) {
        self.name = name
        self.sha1Key = NinebotCrypto.deriveKey(name, NinebotCrypto.fwData)
    }

    // MARK: - Schlüsselwechsel während des Handshakes

    /// Nach der Antwort auf INIT: Schlüssel = SHA-1(Name ‖ BLE-Schlüssel)
    func setBleData(_ data: [UInt8]) {
        bleData = data
        sha1Key = NinebotCrypto.deriveKey(name, data)
    }

    /// Nach bestätigtem PING: Schlüssel = SHA-1(App-Schlüssel ‖ BLE-Schlüssel)
    func setAppData(_ data: [UInt8]) {
        sha1Key = NinebotCrypto.deriveKey(data, bleData ?? NinebotCrypto.fwData)
    }

    /// Macht setAppData rückgängig (Schlüssel = SHA-1(Name ‖ BLE-Schlüssel)).
    func resetToBleData() {
        sha1Key = NinebotCrypto.deriveKey(name, bleData ?? NinebotCrypto.fwData)
    }

    // MARK: - Verschlüsseln / Entschlüsseln

    /// plaintext = [0x5A, 0xA5, LEN, SRC, DST, CMD, INDEX, DATA…]
    /// Ergebnis = Header(3, unverschlüsselt) + Payload(verschlüsselt) + 4 Byte Tag/Prüfsumme + 2 Byte Zähler
    func encrypt(_ plaintext: [UInt8]) -> [UInt8] {
        let header = Array(plaintext.prefix(3))
        let payload = Array(plaintext.dropFirst(3))

        guard counter != 0, bleData != nil else {
            let checksum = UInt16(truncatingIfNeeded: ~payload.reduce(0) { $0 + Int($1) })
            return header + cryptFirst(payload)
                + [0x00, 0x00, UInt8(checksum & 0xFF), UInt8(checksum >> 8), 0x00, 0x00]
        }

        counter &+= 1
        let aes = aesData()
        let tag = mac(header: header, payload: payload, aesData: aes)
        return header + cryptNext(payload, aesData: aes) + tag
            + [UInt8((counter >> 8) & 0xFF), UInt8(counter & 0xFF)]
    }

    /// Entschlüsselt einen vollständigen Frame und übernimmt dessen Zähler.
    /// Ergebnis = [0x5A, 0xA5, LEN, SRC, DST, CMD, INDEX, DATA…]
    func decrypt(_ frame: [UInt8]) -> [UInt8]? {
        guard frame.count >= 9 else { return nil }
        let header = Array(frame.prefix(3))
        let payload = Array(frame[3..<(frame.count - 6)])

        counter = (UInt32(frame[frame.count - 2]) << 8) | UInt32(frame[frame.count - 1])

        if counter == 0 || bleData == nil {
            return header + cryptFirst(payload)
        }
        return header + cryptNext(payload, aesData: aesData())
    }

    // MARK: - Bausteine

    static func deriveKey(_ key1: [UInt8], _ key2: [UInt8]) -> [UInt8] {
        let digest = Insecure.SHA1.hash(data: Data(pad16(key1) + pad16(key2)))
        return Array(digest.prefix(16))
    }

    private static func pad16(_ bytes: [UInt8]) -> [UInt8] {
        Array((bytes + [UInt8](repeating: 0, count: 16)).prefix(16))
    }

    /// [0x01, Zähler (4 Byte, Big-Endian), BLE-Schlüssel[0..<8], 0, 0, 0]
    private func aesData() -> [UInt8] {
        let ble = bleData ?? NinebotCrypto.fwData
        return [0x01,
                UInt8((counter >> 24) & 0xFF), UInt8((counter >> 16) & 0xFF),
                UInt8((counter >> 8) & 0xFF), UInt8(counter & 0xFF)]
            + Array(ble.prefix(8)) + [0x00, 0x00, 0x00]
    }

    /// Einfacher Modus: jeder 16-Byte-Block wird mit AES(Schlüssel, fwData) verknüpft.
    private func cryptFirst(_ input: [UInt8]) -> [UInt8] {
        let keystream = AES128.encryptBlock(key: sha1Key, block: NinebotCrypto.fwData)
        return input.enumerated().map { $1 ^ keystream[$0 % 16] }
    }

    /// SN-Modus: Block i (ab 1) wird mit AES(Schlüssel, aesData mit [15] = i) verknüpft.
    private func cryptNext(_ input: [UInt8], aesData: [UInt8]) -> [UInt8] {
        var block = aesData
        var keystream = [UInt8]()
        var output = [UInt8]()
        for (i, byte) in input.enumerated() {
            if i % 16 == 0 {
                block[15] = UInt8(truncatingIfNeeded: i / 16 + 1)
                keystream = AES128.encryptBlock(key: sha1Key, block: block)
            }
            output.append(byte ^ keystream[i % 16])
        }
        return output
    }

    /// CBC-MAC über Header und Payload, mit AES(Schlüssel, aesData) zu 4 Byte verknüpft.
    private func mac(header: [UInt8], payload: [UInt8], aesData: [UInt8]) -> [UInt8] {
        var b0 = aesData
        b0[0] = 0x59
        b0[15] = UInt8(truncatingIfNeeded: payload.count)
        var x = AES128.encryptBlock(key: sha1Key, block: b0)

        x = AES128.encryptBlock(key: sha1Key, block: xor(x, NinebotCrypto.pad16(header)))

        var offset = 0
        while offset < payload.count {
            let chunk = Array(payload[offset..<min(offset + 16, payload.count)])
            x = AES128.encryptBlock(key: sha1Key, block: xor(x, NinebotCrypto.pad16(chunk)))
            offset += 16
        }

        var a0 = aesData
        a0[15] = 0
        let s0 = AES128.encryptBlock(key: sha1Key, block: a0)
        return Array(xor(x, s0).prefix(4))
    }

    private func xor(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        zip(a, b).map { $0 ^ $1 }
    }
}

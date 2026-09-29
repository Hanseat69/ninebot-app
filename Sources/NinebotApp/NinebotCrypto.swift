//
//  NinebotCrypto.swift
//  Implementierung des "Encryption2"-Protokolls, das Segway-Ninebot-Fahrzeuge
//  verwenden: AES-128 in einem eigenen CTR-ähnlichen Modus mit CBC-MAC-Authentifizierung
//  (ähnlich, aber nicht identisch mit NIST CCM).
//
//  Von der Community per Reverse Engineering der offiziellen App dokumentiert,
//  veröffentlicht zur Interoperabilität gemäß EU-Richtlinie 2009/24/EG Art. 6.
//  Nur zur Verwendung mit dem EIGENEN Fahrzeug.
//

import Foundation
import CryptoKit

enum NinebotCrypto {

    // MARK: - Schlüsselableitung

    /// aes_key = SHA-1(key1_pad16 ‖ key2_pad16)[0:16]
    static func deriveKey(key1: [UInt8], key2: [UInt8]?) -> [UInt8] {
        let k1 = pad16(key1)
        let k2 = key2.map { pad16($0) } ?? [UInt8](repeating: 0, count: 16)
        let digest = Insecure.SHA1.hash(data: Data(k1 + k2))
        return Array(digest.prefix(16))
    }

    private static func pad16(_ bytes: [UInt8]) -> [UInt8] {
        var b = Array(bytes.prefix(16))
        while b.count < 16 { b.append(0) }
        return b
    }

    // MARK: - Nonce

    /// nonce[13] = counter_BE[4] ‖ auth[0:8] ‖ 0x00
    static func buildNonce(counter: UInt32, auth: [UInt8]) -> [UInt8] {
        var nonce = [UInt8]()
        nonce.append(UInt8((counter >> 24) & 0xFF))
        nonce.append(UInt8((counter >> 16) & 0xFF))
        nonce.append(UInt8((counter >> 8) & 0xFF))
        nonce.append(UInt8(counter & 0xFF))
        nonce.append(contentsOf: Array(auth.prefix(8)))
        nonce.append(0x00)
        return nonce
    }

    // MARK: - SN-Modus-Verschlüsselung (nach PRE_COMM, counter > 0)

    /// plaintext = [0x5A, 0xA5, LEN] + payload (SRC/TARGET/CMD/INDEX/DATA)
    /// Gibt den vollständigen Frame zurück: header(3, plain) + ct(payload.count) + enc_tag(4) + counter_BE(2)
    static func encryptSN(key: [UInt8], plaintext: [UInt8], counter: UInt32, auth: [UInt8]) -> [UInt8] {
        let header = Array(plaintext.prefix(3))
        let payload = Array(plaintext.dropFirst(3))
        let nonce = buildNonce(counter: counter, auth: auth)

        let rawTag = cbcMac(key: key, header: header, payload: payload, nonce: nonce)

        var ct = [UInt8]()
        var blockIndex: UInt8 = 1
        var offset = 0
        while offset < payload.count {
            let aBlock: [UInt8] = [0x01] + nonce + [0x00, blockIndex]
            let keystream = AES128.encryptBlock(key: key, block: aBlock)
            let end = min(offset + 16, payload.count)
            for j in offset..<end {
                ct.append(payload[j] ^ keystream[j - offset])
            }
            offset += 16
            blockIndex &+= 1
        }

        let a0: [UInt8] = [0x01] + nonce + [0x00, 0x00]
        let a0Keystream = AES128.encryptBlock(key: key, block: a0)
        let encTag = zip(rawTag, a0Keystream.prefix(4)).map { $0 ^ $1 }

        var frame = header
        frame.append(contentsOf: ct)
        frame.append(contentsOf: encTag)
        frame.append(UInt8((counter >> 8) & 0xFF))
        frame.append(UInt8(counter & 0xFF))
        return frame
    }

    /// CBC-MAC über [header(3) + payload], zurückgegeben als 4-Byte-Tag
    private static func cbcMac(key: [UInt8], header: [UInt8], payload: [UInt8], nonce: [UInt8]) -> [UInt8] {
        let payloadLen = UInt8(payload.count & 0xFF)
        let b0: [UInt8] = [0x59] + nonce + [0x00, payloadLen]
        var x = AES128.encryptBlock(key: key, block: b0)

        var aad = header
        while aad.count < 16 { aad.append(0) }
        x = AES128.encryptBlock(key: key, block: zip(x, aad).map { $0 ^ $1 })

        var offset = 0
        while offset < payload.count {
            var block = Array(payload[offset..<min(offset+16, payload.count)])
            while block.count < 16 { block.append(0) }
            x = AES128.encryptBlock(key: key, block: zip(x, block).map { $0 ^ $1 })
            offset += 16
        }
        return Array(x.prefix(4))
    }

    // MARK: - Non-SN-Modus-Verschlüsselung (nur PRE_COMM-Request, counter == 0)

    static func encryptNonSN(key: [UInt8], plaintext: [UInt8]) -> [UInt8] {
        let header = Array(plaintext.prefix(3))
        let payload = Array(plaintext.dropFirst(3))

        var checksum: Int = 0
        for b in payload { checksum += Int(b) }
        let checksumVal = UInt16((~checksum) & 0xFFFF)

        let keystream = AES128.encryptBlock(key: key, block: [UInt8](repeating: 0, count: 16))

        var ct = [UInt8]()
        var offset = 0
        while offset < payload.count {
            let end = min(offset + 16, payload.count)
            for j in offset..<end {
                ct.append(payload[j] ^ keystream[j - offset])
            }
            offset += 16
        }

        var frame = header
        frame.append(contentsOf: ct)
        frame.append(0x00)
        frame.append(0x00)
        frame.append(UInt8((checksumVal) & 0xFF))
        frame.append(UInt8((checksumVal >> 8) & 0xFF))
        frame.append(0x00)
        frame.append(0x00)
        return frame
    }

    // MARK: - Entschlüsselung (Antwort des Scooters)

    enum DecryptError: Error {
        case tooShort
        case macMismatch
        case replay
    }

    /// Dekodiert einen empfangenen Frame. Bestimmt selbst SN vs. Non-SN anhand der
    /// Counter-Bytes am Ende (counter == 0 → Non-SN-Modus).
    static func decrypt(key: [UInt8], ciphertext: [UInt8], auth: [UInt8]) throws -> (plaintext: [UInt8], counter: UInt32) {
        guard ciphertext.count >= 3 + 6 else { throw DecryptError.tooShort }

        let header = Array(ciphertext.prefix(3))
        let body = Array(ciphertext.dropFirst(3))
        let trailer = Array(body.suffix(6))
        let encPayload = Array(body.dropLast(6))

        let counter = (UInt32(trailer[4]) << 8) | UInt32(trailer[5])

        if counter == 0 {
            // Non-SN-Modus: gleicher statischer Keystream, Prüfsumme statt MAC
            let keystream = AES128.encryptBlock(key: key, block: [UInt8](repeating: 0, count: 16))
            var payload = [UInt8]()
            var offset = 0
            while offset < encPayload.count {
                let end = min(offset + 16, encPayload.count)
                for j in offset..<end {
                    payload.append(encPayload[j] ^ keystream[j - offset])
                }
                offset += 16
            }
            return (header + payload, 0)
        } else {
            let nonce = buildNonce(counter: counter, auth: auth)
            var payload = [UInt8]()
            var blockIndex: UInt8 = 1
            var offset = 0
            while offset < encPayload.count {
                let aBlock: [UInt8] = [0x01] + nonce + [0x00, blockIndex]
                let keystream = AES128.encryptBlock(key: key, block: aBlock)
                let end = min(offset + 16, encPayload.count)
                for j in offset..<end {
                    payload.append(encPayload[j] ^ keystream[j - offset])
                }
                offset += 16
                blockIndex &+= 1
            }

            // Tag verifizieren
            let a0: [UInt8] = [0x01] + nonce + [0x00, 0x00]
            let a0Keystream = AES128.encryptBlock(key: key, block: a0)
            let encTag = Array(trailer.prefix(4))
            let rawTag = zip(encTag, a0Keystream.prefix(4)).map { $0 ^ $1 }

            let expectedTag = cbcMac(key: key, header: header, payload: payload, nonce: nonce)
            guard rawTag == expectedTag else { throw DecryptError.macMismatch }

            return (header + payload, counter)
        }
    }
}

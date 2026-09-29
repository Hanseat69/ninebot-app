//
//  ErrorCodes.swift
//  Fehlercodes laut Produkt-Handbuch F2 / F2 Plus / F2 Pro, Abschnitt 6 „Häufige Fehler“.
//

import Foundation

struct ScooterErrorCode: Identifiable {
    let code: Int
    let cause: String
    let solution: String

    var id: Int { code }

    private static let dealer = "Bitte an den Kundendienst oder einen autorisierten Händler wenden."

    static let all: [ScooterErrorCode] = [
        ScooterErrorCode(code: 10, cause: "Bluetooth-Kommunikationsfehler",
                         solution: "Anschluss des Kommunikations- und Steuerkabels der Anzeigetafel prüfen. " + dealer),
        ScooterErrorCode(code: 11, cause: "Anormale 1A-Phasenstrom-Abtastung des Motors", solution: dealer),
        ScooterErrorCode(code: 12, cause: "Anormale 1B-Phasenstrom-Abtastung des Motors", solution: dealer),
        ScooterErrorCode(code: 13, cause: "Anormale 1C-Phasenstrom-Abtastung des Motors", solution: dealer),
        ScooterErrorCode(code: 14, cause: "Anormale Abtastung des Gasgriff-Hallsensors",
                         solution: "Prüfen, ob der Gasgriff beim Einschalten gedrückt ist. " + dealer),
        ScooterErrorCode(code: 15, cause: "Anormale Abtastung des Brems-Hallsensors",
                         solution: "Prüfen, ob der Bremshebel beim Einschalten betätigt wird. " + dealer),
        ScooterErrorCode(code: 18, cause: "Anormales Motor-Hall-Signal",
                         solution: "Prüfen, ob die Steckbuchse des Hall-Sensors locker ist. " + dealer),
        ScooterErrorCode(code: 21, cause: "Ausfall der Akkukommunikation",
                         solution: "Prüfen, ob das Kommunikationskabel zwischen Akku und Controller locker ist. " + dealer),
        ScooterErrorCode(code: 23, cause: "Standard-Seriennummer des Akkus", solution: dealer),
        ScooterErrorCode(code: 24, cause: "Anormale Standardspannung",
                         solution: "Prüfen, ob das Verbindungskabel zwischen Akku und Controller locker ist. " + dealer),
        ScooterErrorCode(code: 26, cause: "Anormales Schreiben/Lesen von Daten", solution: dealer),
        ScooterErrorCode(code: 31, cause: "Falscher FLASH-Betrieb", solution: dealer),
        ScooterErrorCode(code: 35, cause: "Standard-Seriennummer des KickScooters",
                         solution: "Prüfen, ob der KickScooter noch die Standard-Seriennummer aufweist."),
        ScooterErrorCode(code: 39, cause: "Anormale Akkutemperatur",
                         solution: "Arbeitsumgebung des Akkus prüfen (zu heiß/zu kalt). " + dealer),
        ScooterErrorCode(code: 40, cause: "Anormaler Controller-NTC (Temperatursensor)",
                         solution: "Offener Stromkreis oder Kurzschluss am Controller-Temperatursensor. " + dealer),
        ScooterErrorCode(code: 41, cause: "Anormaler Motor-NTC (Temperatursensor)",
                         solution: "Offener Stromkreis oder Kurzschluss am Motor-Temperatursensor. " + dealer),
        ScooterErrorCode(code: 45, cause: "Anormale Abtastung des BUS-Stroms", solution: dealer),
    ]

    static func lookup(_ code: Int) -> ScooterErrorCode? {
        all.first { $0.code == code }
    }

    /// Kurztext für die Anzeige des Fehlerregisters.
    static func describe(_ code: Int) -> String {
        if code == 0 { return "Keiner" }
        if let known = lookup(code) { return "\(code) – \(known.cause)" }
        return "\(code)"
    }
}

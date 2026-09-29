//
//  HelpView.swift
//  Tab „Hilfe“: Kurzfassung des Produkt-Handbuchs für den F2 Pro, Fehlercodes,
//  Wartungsplan, die Original-Anleitung als PDF und eine Anleitung zur App.
//  Alles liegt in der App und funktioniert ohne Internet.
//

import SwiftUI
import PDFKit

struct HelpView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ManualPDFView()
                    } label: {
                        Label("Original-Anleitung (PDF)", systemImage: "book")
                    }
                } footer: {
                    Text("Deutsche Seiten des Produkt-Handbuchs Segway-Ninebot KickScooter F2 / F2 Plus / F2 Pro.")
                }

                Section("F2 Pro") {
                    NavigationLink { OperationHelp() } label: {
                        Label("Bedienung und Fahrmodi", systemImage: "power")
                    }
                    NavigationLink { SpecsHelp() } label: {
                        Label("Technische Daten", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink { ChargingHelp() } label: {
                        Label("Laden, Akku und Reifen", systemImage: "bolt.batteryblock")
                    }
                    NavigationLink { ErrorCodesHelp() } label: {
                        Label("Fehlercodes", systemImage: "exclamationmark.triangle")
                    }
                    NavigationLink { MaintenanceView() } label: {
                        Label("Wartungsplan", systemImage: "wrench.and.screwdriver")
                    }
                }

                Section("Diese App") {
                    NavigationLink { AppHelp() } label: {
                        Label("So funktioniert die App", systemImage: "questionmark.circle")
                    }
                }
            }
            .navigationTitle("Hilfe")
        }
    }
}

// MARK: - Original-PDF

private struct ManualPDFView: View {
    private let url = Bundle.main.url(forResource: "Anleitung-F2", withExtension: "pdf")

    var body: some View {
        Group {
            if let url = url {
                PDFKitView(url: url)
                    .ignoresSafeArea(edges: .bottom)
                    .toolbar {
                        ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    }
            } else {
                Text("Anleitung nicht gefunden.").foregroundColor(.secondary)
            }
        }
        .navigationTitle("Anleitung")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(url: url)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}

// MARK: - Kurzfassung

private struct HelpText: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct OperationHelp: View {
    var body: some View {
        List {
            Section("Startknopf") {
                HelpText(title: "Ein / Aus", text: "Kurz drücken zum Einschalten. 3 Sekunden gedrückt halten zum Ausschalten.")
                HelpText(title: "Licht", text: "Im eingeschalteten Zustand kurz drücken: Scheinwerfer und Rücklicht an/aus. Beim deutschen Modell (051203D) sind die Lichter dauerhaft an und lassen sich nicht ausschalten.")
                HelpText(title: "Fahrmodus wechseln", text: "Doppelt drücken, um zwischen den Geschwindigkeitsmodi zu wechseln.")
            }
            Section("Fahrmodi F2 Pro") {
                ValueRow(title: "ECO (Energiesparmodus)", value: "15 km/h")
                ValueRow(title: "D (Standardmodus)", value: "20 km/h")
                ValueRow(title: "S (Sportmodus)", value: "20 km/h (D-Version) · 25 km/h (E-Version)")
                HelpText(title: "Gehmodus", text: "Max. 5 km/h. Aktivieren in der Segway-App: Menü > Einstellungen > Gehmodus.")
            }
            Section("Blinker, Hupe, Klingel") {
                HelpText(title: "Blinker", text: "Am Blinkerschalter links (←) oder rechts (→) drücken. Erneut drücken zum Ausschalten.")
                HelpText(title: "Hupe (nur F2 Pro)", text: "Hupentaste am linken Lenkergriff.")
            }
            Section("Armaturenbrett") {
                HelpText(title: "Tacho", text: "Zeigt die Geschwindigkeit und bei Störungen einen Fehlercode (siehe Fehlercodes).")
                HelpText(title: "Akkustand", text: "5 Balken. Leuchtet nur noch der erste Balken rot, den Scooter sofort laden.")
                HelpText(title: "Bluetooth-Symbol", text: "Der Scooter ist mit einem Handy gekoppelt.")
            }
        }
        .navigationTitle("Bedienung")
    }
}

private struct SpecsHelp: View {
    var body: some View {
        List {
            Section {
                ValueRow(title: "Modell", value: "051203D (Deutschland) · 051203E")
                ValueRow(title: "Höchstgeschwindigkeit", value: "ca. 20 km/h (D) · 25 km/h (E)")
                ValueRow(title: "Reichweite (theoretisch)", value: "ca. 55 km")
                ValueRow(title: "Max. Steigung", value: "ca. 22 %")
                ValueRow(title: "Motor", value: "450 W, max. 900 W")
            } header: {
                Text("Fahren")
            } footer: {
                Text("Reichweite gemessen mit vollem Akku, 75 kg Last, 25 °C, 70 % der Höchstgeschwindigkeit auf durchschnittlicher Straße. Tempo, Gewicht, Anfahren/Bremsen und Temperatur verringern sie.")
            }
            Section("Maße und Gewicht") {
                ValueRow(title: "Aufgeklappt (L × B × H)", value: "ca. 1159 × 570 × 1252 mm")
                ValueRow(title: "Zusammengeklappt", value: "ca. 1159 × 570 × 529 mm")
                ValueRow(title: "Gewicht", value: "ca. 18,5 kg")
                ValueRow(title: "Zuladung", value: "max. 120 kg")
                ValueRow(title: "Fahrer", value: "16–55 Jahre, 120–200 cm")
            }
            Section("Akku und Ladegerät") {
                ValueRow(title: "Akku", value: "36 V, 12,8 Ah, 460 Wh")
                ValueRow(title: "Max. Ladespannung", value: "42 V")
                ValueRow(title: "Ladedauer", value: "ca. 8 h")
                ValueRow(title: "Ladegerät", value: "100–240 V, 42 V / 1,7 A, 70 W")
            }
            Section("Umgebung") {
                ValueRow(title: "Betriebstemperatur", value: "−10 bis 40 °C")
                ValueRow(title: "Ladetemperatur", value: "0 bis 45 °C")
                ValueRow(title: "Lagertemperatur", value: "−10 bis 50 °C (empfohlen 10–30 °C)")
                ValueRow(title: "Schutzklasse", value: "IPX5 (spritzwassergeschützt)")
            }
            Section("Reifen") {
                ValueRow(title: "Reifen", value: "10 Zoll, schlauchlos, selbstdichtend")
                ValueRow(title: "Reifendruck (techn. Daten)", value: "42–48 psi (ca. 2,9–3,3 bar)")
            }
        }
        .navigationTitle("Technische Daten")
    }
}

private struct ChargingHelp: View {
    var body: some View {
        List {
            Section("Laden") {
                HelpText(title: "Ladegerät-LED", text: "Rot = lädt, grün = voll geladen.")
                HelpText(title: "Temperatur", text: "Nur zwischen 0 und 45 °C laden.")
                HelpText(title: "Lagerung", text: "Bei längerer Lagerung alle 60 Tage aufladen. Empfohlene Lagertemperatur 10–30 °C.")
            }
            Section("Akku-Lebensdauer") {
                HelpText(title: "Austausch", text: "Laut Hersteller nach 500 Lade-/Entladezyklen oder mehr als 10.000 km Gesamtlaufleistung. Den Akkuzustand zeigt der Tab „Akku“.")
            }
            Section {
                HelpText(title: "Laut Wartungsplan", text: "50–55 psi (ca. 3,4–3,8 bar), alle 3 Monate prüfen.")
                HelpText(title: "Laut technischen Daten", text: "42–48 psi (ca. 2,9–3,3 bar).")
            } header: {
                Text("Reifendruck")
            } footer: {
                Text("Das Handbuch widerspricht sich hier. Im Zweifel die Angabe auf der Reifenflanke beachten oder beim Händler nachfragen.")
            }
        }
        .navigationTitle("Laden, Akku, Reifen")
    }
}

private struct ErrorCodesHelp: View {
    @EnvironmentObject private var model: ScooterModel
    @State private var search = ""

    private var codes: [ScooterErrorCode] {
        let text = search.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return ScooterErrorCode.all }
        return ScooterErrorCode.all.filter {
            String($0.code).hasPrefix(text) || $0.cause.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        List(codes) { code in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(code.code) – \(code.cause)").font(.headline)
                Text(code.solution).font(.subheadline).foregroundColor(.secondary)
            }
            .padding(.vertical, 2)
        }
        .searchable(text: $search, prompt: "Code oder Stichwort")
        .navigationTitle("Fehlercodes")
    }
}

private struct AppHelp: View {
    var body: some View {
        List {
            Section("Erste Verbindung") {
                HelpText(title: "1. Scooter einschalten", text: "Im Tab „Scooter“ auf „Scooter suchen“ tippen und deinen Scooter in der Liste wählen.")
                HelpText(title: "2. Koppeln", text: "Fordert die App dazu auf, den Startknopf am Scooter kurz drücken (innerhalb von 60 Sekunden).")
                HelpText(title: "3. Fertig", text: "Die App merkt sich den Scooter. Ab jetzt verbindet sie sich beim Einschalten von selbst.")
            }
            Section("Automatik und Fahrtenbuch") {
                HelpText(title: "Aufzeichnung", text: "Solange der Scooter verbunden ist, wird die Fahrt aufgezeichnet. Beim Ausschalten wird sie gespeichert (ab 1 Minute und 100 m).")
                HelpText(title: "Standort „Immer“", text: "Nötig, damit die Aufzeichnung auch im Hintergrund startet. Die App fragt danach.")
                HelpText(title: "App nicht wegwischen", text: "Wird die App aus der App-Übersicht entfernt, schaltet iOS die Automatik ab, bis du sie wieder öffnest.")
                HelpText(title: "Sperrbildschirm", text: "Tempo, Akku und Strecke erscheinen während der Fahrt auf dem Sperrbildschirm. Startet eine Fahrt im Hintergrund, erscheint die Anzeige nach dem ersten Öffnen der App.")
            }
            Section("Route") {
                HelpText(title: "Reichweitenprüfung", text: "Ziel suchen: Die App vergleicht die Strecke mit der Restreichweite des Scooters und übergibt die Route an Apple Maps.")
            }
            Section("Datenschutz") {
                HelpText(title: "Auf dem iPhone", text: "Fahrten, Akku-Verlauf und Wartung werden nur auf deinem iPhone gespeichert. Kein Konto, keine Werbung, kein Tracking.")
                HelpText(title: "Internet", text: "Karten, Adressen und Routen kommen von Apple Karten. Wetter (nur wenn eingeschaltet) von Open-Meteo, mit auf ca. 1 km gerundetem Standort.")
            }
        }
        .navigationTitle("Über die App")
    }
}

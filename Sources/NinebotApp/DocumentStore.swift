//
//  DocumentStore.swift
//  Ablage für Versicherungsbestätigung, Betriebserlaubnis, Kaufbeleg usw.
//
//  - Die Dokumente liegen als PDF im App-Ordner, mit iOS-Dateischutz
//    „complete“: verschlüsselt, solange das iPhone gesperrt ist.
//  - Nichts davon verlässt das iPhone (außer im normalen iPhone-Backup).
//  - Optional mit Face ID / Code geschützt.
//

import Foundation
import UIKit
import PDFKit
import LocalAuthentication
import UserNotifications

enum DocumentKind: String, Codable, CaseIterable, Identifiable {
    case insurance, permit, receipt, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .insurance: return "Versicherungsbestätigung"
        case .permit: return "Betriebserlaubnis / Datenbestätigung"
        case .receipt: return "Kaufbeleg / Rechnung"
        case .other: return "Sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .insurance: return "checkmark.shield"
        case .permit: return "doc.text"
        case .receipt: return "cart"
        case .other: return "doc"
        }
    }

    /// Ein neues Dokument dieser Art ersetzt das bisherige (das wandert ins Archiv).
    var replacesPrevious: Bool { self == .insurance || self == .permit }

    var dateLabel: String {
        switch self {
        case .insurance: return "Gültig bis"
        case .receipt: return "Garantie bis"
        default: return "Gültig bis"
        }
    }
}

struct ScooterDocument: Codable, Identifiable {
    var id = UUID()
    var kind: DocumentKind
    var title: String
    var insurer: String = ""
    var plate: String = ""
    var contractNumber: String = ""
    var validUntil: Date?
    var notes: String = ""
    var fileName: String
    var added = Date()
    var archived = false

    var isExpired: Bool {
        guard let date = validUntil else { return false }
        return date < Calendar.current.startOfDay(for: Date())
    }

    var expiresSoon: Bool {
        guard let date = validUntil, !isExpired else { return false }
        return date.timeIntervalSinceNow < 30 * 24 * 3600
    }
}

final class DocumentStore: ObservableObject {

    @Published private(set) var documents: [ScooterDocument] = []
    @Published private(set) var isUnlocked = false
    @Published private(set) var lockError: String?

    @Published var requireFaceID: Bool = true {
        didSet { UserDefaults.standard.set(requireFaceID, forKey: Keys.requireFaceID) }
    }
    @Published var keepArchive: Bool = true {
        didSet { UserDefaults.standard.set(keepArchive, forKey: Keys.keepArchive) }
    }

    private enum Keys {
        static let requireFaceID = "documents.requireFaceID"
        static let keepArchive = "documents.keepArchive"
    }

    private let folder: URL
    private let indexURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Dokumente", isDirectory: true)
        indexURL = folder.appendingPathComponent("dokumente.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _requireFaceID = Published(initialValue: UserDefaults.standard.object(forKey: Keys.requireFaceID) as? Bool ?? true)
        _keepArchive = Published(initialValue: UserDefaults.standard.object(forKey: Keys.keepArchive) as? Bool ?? true)
        reload()
    }

    /// Die Liste (ohne Dateiinhalte) ist auch nach einem Hintergrundstart lesbar,
    /// sobald das iPhone seit dem Neustart einmal entsperrt wurde.
    func reload() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? decoder.decode([ScooterDocument].self, from: data) {
            documents = saved
        }
    }

    var current: [ScooterDocument] { documents.filter { !$0.archived } }
    var archive: [ScooterDocument] { documents.filter { $0.archived }.sorted { $0.added > $1.added } }
    var currentInsurance: ScooterDocument? { current.first { $0.kind == .insurance } }

    func fileURL(for document: ScooterDocument) -> URL {
        folder.appendingPathComponent(document.fileName)
    }

    // MARK: - Face ID

    var isAccessible: Bool { !requireFaceID || isUnlocked }

    func unlock() {
        lockError = nil
        let context = LAContext()
        var error: NSError?
        // Face ID/Touch ID, ersatzweise der iPhone-Code.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            lockError = "Auf diesem iPhone ist kein Code eingerichtet — ein Schutz ist so nicht möglich."
            isUnlocked = true
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Scooter-Dokumente anzeigen") { success, _ in
            DispatchQueue.main.async {
                self.isUnlocked = success
                if !success { self.lockError = "Nicht entsperrt." }
            }
        }
    }

    func lock() {
        isUnlocked = false
    }

    // MARK: - Ändern

    func add(_ document: ScooterDocument, pdf: Data) {
        var document = document
        document.fileName = "\(document.id.uuidString).pdf"
        guard write(pdf, to: fileURL(for: document)) else { return }

        if document.kind.replacesPrevious {
            for old in current where old.kind == document.kind {
                if keepArchive {
                    setArchived(old.id, true, save: false)
                } else {
                    remove(old, save: false)
                }
            }
        }
        documents.append(document)
        save()
    }

    func update(_ document: ScooterDocument, newPDF: Data? = nil) {
        guard let i = documents.firstIndex(where: { $0.id == document.id }) else { return }
        if let pdf = newPDF {
            _ = write(pdf, to: fileURL(for: document))
        }
        documents[i] = document
        save()
    }

    func setArchived(_ id: UUID, _ archived: Bool, save shouldSave: Bool = true) {
        guard let i = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[i].archived = archived
        if shouldSave { save() }
    }

    func delete(_ document: ScooterDocument) {
        remove(document, save: true)
    }

    private func remove(_ document: ScooterDocument, save shouldSave: Bool) {
        try? FileManager.default.removeItem(at: fileURL(for: document))
        documents.removeAll { $0.id == document.id }
        if shouldSave { save() }
    }

    /// Kopie mit lesbarem Namen zum Teilen (z. B. „Versicherungsbestaetigung-2027.pdf“).
    func shareURL(for document: ScooterDocument) -> URL? {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Teilen", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = document.title.isEmpty ? document.kind.title : document.title
        let safe = base.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let year = document.validUntil.map { "-\(Calendar.current.component(.year, from: $0))" } ?? ""
        let url = folder.appendingPathComponent("\(safe)\(year).pdf")
        do {
            try FileManager.default.copyItem(at: fileURL(for: document), to: url)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Hilfen

    /// Ende des Versicherungsjahres für E-Scooter: letzter Tag im Februar.
    static func insuranceYearEnd(from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let endYear = calendar.component(.month, from: date) >= 3 ? year + 1 : year
        let march1 = calendar.date(from: DateComponents(year: endYear, month: 3, day: 1)) ?? date
        return calendar.date(byAdding: .day, value: -1, to: march1) ?? date
    }

    /// Fügt Bilder (Scan, Fotos) als Seiten an ein PDF an.
    static func makePDF(base: Data?, images: [UIImage]) -> Data? {
        let document = base.flatMap { PDFDocument(data: $0) } ?? PDFDocument()
        for image in images {
            if let page = PDFPage(image: downscaled(image)) {
                document.insert(page, at: document.pageCount)
            }
        }
        return document.pageCount > 0 ? document.dataRepresentation() : nil
    }

    private static func downscaled(_ image: UIImage, maxSide: CGFloat = 2000) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func write(_ data: Data, to url: URL) -> Bool {
        (try? data.write(to: url, options: [.atomic, .completeFileProtection])) != nil
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(documents) {
            try? data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        scheduleReminders()
    }

    // MARK: - Erinnerungen

    /// 4 Wochen und 1 Woche vorher sowie am Ablauftag, jeweils um 10 Uhr.
    private func scheduleReminders() {
        let center = UNUserNotificationCenter.current()
        let offsets = [28, 7, 0]
        let identifiers = documents.flatMap { doc in offsets.map { "document-\(doc.id.uuidString)-\($0)" } }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        for doc in current {
            guard let until = doc.validUntil else { continue }
            for days in offsets {
                guard let day = Calendar.current.date(byAdding: .day, value: -days, to: until), day > Date() else { continue }
                let content = UNMutableNotificationContent()
                if doc.kind == .insurance {
                    content.title = days == 0 ? "Versicherung läuft heute ab" : "Neue Versicherung für den Scooter"
                    content.body = days == 0
                        ? "Ab morgen brauchst du ein neues Versicherungskennzeichen. Neue Bestätigung in der App hinterlegen."
                        : "Das Versicherungsjahr endet am \(until.formatted(date: .long, time: .omitted)). Neues Kennzeichen besorgen und die Bestätigung in der App austauschen."
                } else {
                    content.title = "\(doc.kind.dateLabel) \(until.formatted(date: .abbreviated, time: .omitted))"
                    content.body = doc.title.isEmpty ? doc.kind.title : doc.title
                }
                content.sound = .default
                var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
                components.hour = 10
                center.add(UNNotificationRequest(
                    identifier: "document-\(doc.id.uuidString)-\(days)", content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            }
        }
    }

    func requestNotificationPermission() {
        guard !DemoMode.isActive else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

#if DEBUG
// MARK: - Beispieldaten für Screenshots

extension DocumentStore {
    func loadDemo() {
        isUnlocked = true
        for document in documents { try? FileManager.default.removeItem(at: fileURL(for: document)) }
        documents = []

        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: DocumentStore.insuranceYearEnd()) ?? Date()
        add(ScooterDocument(kind: .insurance, title: "Versicherung 2025/26", insurer: "Muster-Versicherung AG",
                            plate: "812 KLM", contractNumber: "KV-2025-004711", validUntil: lastYear, fileName: ""),
            pdf: DocumentStore.demoPDF(title: "Versicherungsbestätigung 2025/26", lines: ["Kennzeichen 812 KLM"]))
        add(ScooterDocument(kind: .insurance, title: "Versicherung 2026/27", insurer: "Muster-Versicherung AG",
                            plate: "347 BXT", contractNumber: "KV-2026-004711",
                            validUntil: DocumentStore.insuranceYearEnd(), fileName: ""),
            pdf: DocumentStore.demoPDF(title: "Versicherungsbestätigung 2026/27",
                                       lines: ["Versicherungskennzeichen: 347 BXT",
                                               "Fahrzeug: Segway-Ninebot KickScooter F2 Pro D",
                                               "Versicherungsjahr: 01.03.2026 – 28.02.2027",
                                               "Haftpflicht, Teilkasko"]))
        add(ScooterDocument(kind: .permit, title: "Datenbestätigung F2 Pro D", fileName: ""),
            pdf: DocumentStore.demoPDF(title: "Datenbestätigung", lines: ["Elektrokleinstfahrzeug nach eKFV",
                                                                          "Modell 051203D", "Höchstgeschwindigkeit 20 km/h"]))
        add(ScooterDocument(kind: .receipt, title: "Rechnung Fachhandel",
                            validUntil: Calendar.current.date(byAdding: .year, value: 2, to: Date()), fileName: ""),
            pdf: DocumentStore.demoPDF(title: "Rechnung", lines: ["Segway-Ninebot F2 Pro D", "699,00 EUR"]))
    }

    static func demoPDF(title: String, lines: [String]) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            let big = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 26)]
            let body = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 16)]
            (title as NSString).draw(at: CGPoint(x: 50, y: 70), withAttributes: big)
            for (i, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 50, y: 130 + CGFloat(i) * 28), withAttributes: body)
            }
            let mark: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 110),
                                                        .foregroundColor: UIColor.systemRed.withAlphaComponent(0.15)]
            ("MUSTER" as NSString).draw(at: CGPoint(x: 80, y: 420), withAttributes: mark)
        }
    }
}
#endif

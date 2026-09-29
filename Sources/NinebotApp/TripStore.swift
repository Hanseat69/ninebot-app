//
//  TripStore.swift
//  Fahrtenbuch und Akku-Verlauf. Wird als JSON im Dokumente-Ordner der App
//  gespeichert, also nur auf dem iPhone (und in dessen Backup).
//

import Foundation
import CoreLocation

struct TripPoint: Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double          // m/s laut GPS, -1 = unbekannt
    let time: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        speed = location.speed
        time = location.timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct Trip: Codable, Identifiable {
    var id = UUID()
    var scooterName: String
    var start: Date
    var end: Date
    var points: [TripPoint] = []
    var gpsDistance: Double = 0       // Meter
    var maxSpeed: Double = 0          // km/h laut GPS
    var startBattery: Int?            // %
    var endBattery: Int?
    var startOdometer: Double?        // km laut Scooter
    var endOdometer: Double?
    var startAddress: String?
    var endAddress: String?
    var weather: WeatherInfo?

    init(scooterName: String, start: Date) {
        self.scooterName = scooterName
        self.start = start
        self.end = start
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var scooterDistance: Double? {
        guard let s = startOdometer, let e = endOdometer, e >= s else { return nil }
        return e - s
    }

    /// Strecke in km: bevorzugt der Kilometerzähler des Scooters, sonst GPS.
    var distanceKm: Double {
        if let d = scooterDistance, d > 0 { return d }
        return gpsDistance / 1000
    }

    var averageSpeed: Double? {
        duration >= 60 ? distanceKm / (duration / 3600) : nil
    }

    var batteryUsed: Int? {
        guard let s = startBattery, let e = endBattery else { return nil }
        return s - e
    }

    /// Akkuverbrauch in Prozentpunkten pro km (erst ab 0,5 km aussagekräftig).
    var consumptionPerKm: Double? {
        guard let used = batteryUsed, used >= 0, distanceKm >= 0.5 else { return nil }
        return Double(used) / distanceKm
    }

    /// Fügt eine GPS-Position hinzu; ungenaue und fast gleiche Punkte werden übersprungen.
    mutating func append(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 30 else { return }
        if let last = points.last {
            let distance = location.distance(from: last.location)
            guard distance >= 3 else { return }
            gpsDistance += distance
        }
        points.append(TripPoint(location))
        if location.speed > 0 {
            maxSpeed = max(maxSpeed, location.speed * 3.6)
        }
    }
}

struct BatterySnapshot: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var percent: Int?
    var health: Int?
    var odometer: Double?
}

final class TripStore: ObservableObject {

    @Published private(set) var trips: [Trip] = []
    @Published private(set) var snapshots: [BatterySnapshot] = []

    private let folder: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let tripsFile = "fahrten.json"
    private static let snapshotsFile = "akku.json"
    private static let activeFile = "aktuelle-fahrt.json"

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = documents.appendingPathComponent("Fahrtenbuch", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        trips = load([Trip].self, from: TripStore.tripsFile) ?? []
        snapshots = load([BatterySnapshot].self, from: TripStore.snapshotsFile) ?? []
    }

    // MARK: - Fahrten

    func add(_ trip: Trip) {
        trips.insert(trip, at: 0)
        trips.sort { $0.start > $1.start }
        save(trips, to: TripStore.tripsFile)
    }

    func update(_ trip: Trip) {
        guard let i = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[i] = trip
        save(trips, to: TripStore.tripsFile)
    }

    func delete(at offsets: IndexSet) {
        trips.remove(atOffsets: offsets)
        save(trips, to: TripStore.tripsFile)
    }

    func delete(id: UUID) {
        trips.removeAll { $0.id == id }
        save(trips, to: TripStore.tripsFile)
    }

    /// Zwischenstand der laufenden Fahrt, damit sie einen App-Abbruch übersteht.
    func saveActive(_ trip: Trip?) {
        let url = folder.appendingPathComponent(TripStore.activeFile)
        if let trip = trip {
            save(trip, to: TripStore.activeFile)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func loadActive() -> Trip? {
        load(Trip.self, from: TripStore.activeFile)
    }

    // MARK: - Akku-Verlauf

    /// Höchstens ein Eintrag pro Tag; der neueste gewinnt.
    func addSnapshot(_ snapshot: BatterySnapshot) {
        snapshots.removeAll { Calendar.current.isDate($0.date, inSameDayAs: snapshot.date) }
        snapshots.append(snapshot)
        snapshots.sort { $0.date < $1.date }
        save(snapshots, to: TripStore.snapshotsFile)
    }

    // MARK: - Export

    /// Schreibt die Strecke als GPX-Datei (lesbar von Komoot, Strava, Google Earth …).
    func gpxFile(for trip: Trip) -> URL? {
        guard !trip.points.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="NinebotApp" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>Fahrt \(iso.string(from: trip.start))</name><trkseg>

        """
        for p in trip.points {
            gpx += "<trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\"><ele>\(p.altitude)</ele>"
                + "<time>\(iso.string(from: p.time))</time></trkpt>\n"
        }
        gpx += "</trkseg></trk>\n</gpx>\n"

        let name = DateFormatter.fileName.string(from: trip.start)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Fahrt-\(name).gpx")
        do {
            try gpx.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Alle GPS-Punkte einer Fahrt als CSV (deutsches Excel-Format: ; und Dezimalkomma).
    func csvFile(for trip: Trip) -> URL? {
        guard !trip.points.isEmpty else { return nil }
        var csv = "Zeit;Breitengrad;Längengrad;Höhe (m);Geschwindigkeit (km/h)\n"
        for p in trip.points {
            csv += [DateFormatter.csv.string(from: p.time),
                    TripStore.number(p.latitude, 6), TripStore.number(p.longitude, 6),
                    TripStore.number(p.altitude, 1),
                    p.speed >= 0 ? TripStore.number(p.speed * 3.6, 1) : ""].joined(separator: ";") + "\n"
        }
        return write(csv, name: "Fahrt-\(DateFormatter.fileName.string(from: trip.start)).csv")
    }

    /// Übersicht aller Fahrten als CSV.
    func csvFileForAllTrips() -> URL? {
        var csv = "Datum;Abfahrt;Ankunft;Dauer (min);Strecke (km);Ø km/h;Max km/h (GPS);"
            + "Akku Start (%);Akku Ende (%);Verbrauch (%/km);Start;Ziel;Wetter\n"
        for t in trips.reversed() {
            let fields: [String] = [
                t.start.formatted(date: .numeric, time: .omitted),
                t.start.formatted(date: .omitted, time: .shortened),
                t.end.formatted(date: .omitted, time: .shortened),
                TripStore.number(t.duration / 60, 0),
                TripStore.number(t.distanceKm, 2),
                t.averageSpeed.map { TripStore.number($0, 1) } ?? "",
                t.maxSpeed > 0 ? TripStore.number(t.maxSpeed, 1) : "",
                t.startBattery.map(String.init) ?? "",
                t.endBattery.map(String.init) ?? "",
                t.consumptionPerKm.map { TripStore.number($0, 1) } ?? "",
                t.startAddress ?? "",
                t.endAddress ?? "",
                t.weather?.shortText ?? "",
            ]
            csv += fields.map(TripStore.csvField).joined(separator: ";") + "\n"
        }
        return write(csv, name: "Fahrtenbuch.csv")
    }

    private func write(_ text: String, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        // Mit BOM, damit Excel die Umlaute richtig erkennt.
        guard let data = ("\u{FEFF}" + text).data(using: .utf8),
              (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private static func number(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", locale: Locale(identifier: "de_DE"), value)
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(";") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Dateien

    private func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(file)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, to file: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: folder.appendingPathComponent(file), options: .atomic)
    }
}

extension DateFormatter {
    static let csv: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy HH:mm:ss"
        return f
    }()

    static let fileName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()
}

#if DEBUG
// MARK: - Beispieldaten für Screenshots

extension TripStore {
    func loadDemo() {
        let routes: [(daysAgo: Int, hour: Int, minute: Int, points: Int, heading: Double, from: String, to: String, temp: Double, code: Int)] = [
            (0, 7, 42, 190, 0.6, "Mönckebergstraße, Hamburg", "Großer Burstah 31, Hamburg", 12, 1),
            (1, 17, 5, 260, 2.2, "Am Sandtorkai 1, Hamburg", "Eppendorfer Weg 88, Hamburg", 16, 2),
            (2, 8, 15, 150, 4.0, "Lange Reihe 12, Hamburg", "Jungfernstieg 7, Hamburg", 9, 3),
            (4, 18, 30, 320, 1.1, "Schanzenstraße 40, Hamburg", "Övelgönne 13, Hamburg", 19, 0),
            (6, 12, 10, 110, 5.2, "Mühlenkamp 23, Hamburg", "Hofweg 60, Hamburg", 7, 61),
            (9, 9, 0, 230, 3.3, "Steindamm 5, Hamburg", "Osterstraße 101, Hamburg", 11, 2),
        ]
        var odometer = 412.7
        var demo: [Trip] = []
        for (index, r) in routes.enumerated() {
            let day = Calendar.current.date(byAdding: .day, value: -r.daysAgo, to: Date()) ?? Date()
            var start = Calendar.current.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: day) ?? day
            if start > Date() { start = Date().addingTimeInterval(-3600) }
            var trip = Trip(scooterName: "F2 Pro 3A1C", start: start)

            var lat = 53.5511 + Double(index) * 0.004
            var lon = 9.9937 - Double(index) * 0.006
            for k in 0..<r.points {
                let t = Double(k)
                let angle = r.heading + 0.7 * sin(t / 30)
                let kmh = max(3, min(21, 14 + 7 * sin(t / 11) + 3 * sin(t / 4.3)))
                let step = kmh / 3.6 * 4
                lat += step * cos(angle) / 111_000
                lon += step * sin(angle) / (111_000 * cos(lat * .pi / 180))
                trip.append(CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                       altitude: 12, horizontalAccuracy: 5, verticalAccuracy: 5,
                                       course: angle * 180 / .pi, speed: kmh / 3.6,
                                       timestamp: start.addingTimeInterval(t * 4)))
            }
            trip.end = start.addingTimeInterval(Double(r.points) * 4 + 20)
            let km = trip.gpsDistance / 1000
            trip.endOdometer = (odometer * 10).rounded() / 10
            trip.startOdometer = trip.endOdometer.map { $0 - km }
            odometer -= km + 1.3
            trip.startBattery = 92 - index * 4
            trip.endBattery = (trip.startBattery ?? 90) - Int((km * 1.9).rounded())
            trip.startAddress = r.from
            trip.endAddress = r.to
            trip.weather = WeatherInfo(time: start, temperature: r.temp, windSpeed: 12, windGusts: 25,
                                       precipitation: 0, rainChance: 10, code: r.code)
            demo.append(trip)
        }
        trips = demo

        snapshots = (0..<6).map { month in
            BatterySnapshot(date: Calendar.current.date(byAdding: .month, value: month - 5, to: Date()) ?? Date(),
                            percent: 80, health: [100, 100, 99, 99, 98, 97][month],
                            odometer: 60 + Double(month) * 70)
        }
    }
}
#endif

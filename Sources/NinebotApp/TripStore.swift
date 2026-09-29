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
    static let fileName: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return f
    }()
}

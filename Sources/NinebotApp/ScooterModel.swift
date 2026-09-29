//
//  ScooterModel.swift
//  Zentrale Logik der App: Verbinden (auch automatisch), Werte lesen,
//  Einstellungen schreiben und Fahrten automatisch aufzeichnen.
//
//  Automatik:
//  - Nach der ersten erfolgreichen Verbindung merkt sich die App den Scooter.
//  - Danach liegt ständig ein Verbindungsauftrag bei iOS. Wird der Scooter
//    eingeschaltet, verbindet iOS — auch wenn die App im Hintergrund ist.
//  - Solange die Verbindung steht, wird eine Fahrt aufgezeichnet. Schaltest du
//    den Scooter aus, wird sie gespeichert (ab 1 Minute und 100 m).
//

import Foundation
import CoreBluetooth
import CoreLocation
import UIKit

struct ScooterValue: Identifiable {
    let id: String
    let title: String
    var text: String
}

struct KnownScooter: Codable, Equatable {
    let id: UUID
    let name: String
}

final class ScooterModel: ObservableObject {

    static let shared = ScooterModel()

    static let speedLimitRange: ClosedRange<Double> = 6...20
    static let kersLevels = ["Aus", "Mittel", "Stark"]

    private enum Keys {
        static let autoConnect = "autoConnect"
        static let knownScooter = "knownScooter"
        static let weatherEnabled = "weatherEnabled"
    }

    // MARK: Verbindung
    @Published private(set) var state: NinebotSessionState = .idle
    @Published private(set) var scooters: [DiscoveredScooter] = []
    @Published private(set) var isScanning = false
    @Published private(set) var connectedName: String?
    @Published private(set) var isWaitingForKnownScooter = false
    @Published private(set) var message: String?

    // MARK: Werte und Einstellungen
    @Published private(set) var liveValues: [ScooterValue] = []
    @Published private(set) var values: [ScooterValue] = []
    @Published private(set) var isReading = false
    @Published var speedLimit: Double = 20
    @Published private(set) var kersLevel: Int?
    @Published private(set) var cruiseControl: Bool?
    @Published private(set) var tailLight: Bool?

    // MARK: Automatik
    @Published private(set) var knownScooter: KnownScooter?
    @Published var autoConnect: Bool = true {
        didSet {
            UserDefaults.standard.set(autoConnect, forKey: Keys.autoConnect)
            if autoConnect {
                autoPaused = false
                handshakeFailures = 0
                connectKnownScooter()
            }
        }
    }
    @Published private(set) var locationStatus: CLAuthorizationStatus = .notDetermined

    // MARK: Fahrtenbuch
    let store = TripStore()
    @Published private(set) var activeTrip: Trip?
    @Published private(set) var gpsSpeed: Double?     // km/h

    // MARK: Zuletzt bekannte Scooterwerte (auch nach dem Trennen)
    @Published private(set) var odometer: Double?        // km
    @Published private(set) var remainingRangeKm: Double?
    @Published private(set) var batteryPercent: Int?

    // MARK: Wartung
    let maintenance = MaintenanceStore()

    // MARK: Wetter (Open-Meteo, nur wenn eingeschaltet)
    @Published var weatherEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(weatherEnabled, forKey: Keys.weatherEnabled)
            if weatherEnabled { refreshWeather(force: true) } else { weather = nil }
        }
    }
    @Published private(set) var weather: WeatherInfo?

    private let bleManager: NinebotBLEManager
    private let session: NinebotSession
    private let location = LocationTracker()
    private let geocoder = CLGeocoder()
    private let liveActivity = LiveActivityController()

    private var currentScooter: KnownScooter?
    private var scanID = 0
    private var pollTimer: Timer?
    private var isPolling = false
    private var autoPaused = false
    private var handshakeFailures = 0
    private var lastActiveSave = Date.distantPast

    private init() {
        let ble = NinebotBLEManager()
        bleManager = ble
        session = NinebotSession(bleManager: ble)
        _autoConnect = Published(initialValue: UserDefaults.standard.object(forKey: Keys.autoConnect) as? Bool ?? true)
        _weatherEnabled = Published(initialValue: UserDefaults.standard.bool(forKey: Keys.weatherEnabled))
        if let data = UserDefaults.standard.data(forKey: Keys.knownScooter) {
            knownScooter = try? JSONDecoder().decode(KnownScooter.self, from: data)
        }

        ble.onDiscover = { [weak self] scooter in self?.add(scooter) }
        ble.onPoweredOn = { [weak self] in self?.connectKnownScooter() }
        session.onStateChange = { [weak self] state in self?.handle(state) }
        location.onLocations = { [weak self] locations in self?.record(locations) }
        location.onAuthorizationChange = { [weak self] status in
            guard let self = self else { return }
            self.locationStatus = status
            if self.activeTrip != nil { self.location.start() }
        }
        locationStatus = location.authorization
        odometer = store.snapshots.last(where: { $0.odometer != nil })?.odometer

        finishInterruptedTrip()
    }

    /// Die App kommt in den Vordergrund.
    func appDidBecomeActive() {
        if let trip = activeTrip, !liveActivity.isRunning {
            liveActivity.start(name: trip.scooterName, start: trip.start, state: liveState)
        }
        refreshWeather(force: false)
    }

    // MARK: - Wetter

    func refreshWeather(force: Bool) {
        guard weatherEnabled else { return }
        if !force, let weather = weather, -weather.time.timeIntervalSinceNow < 15 * 60 { return }
        location.requestOnce { [weak self] location in
            guard let coordinate = location?.coordinate else { return }
            WeatherService.fetch(for: coordinate) { result in
                guard let self = self, case .success(let info) = result else { return }
                self.weather = info
                if self.activeTrip != nil && self.activeTrip?.weather == nil {
                    self.activeTrip?.weather = info
                }
            }
        }
    }

    // MARK: - Live Activity

    private var liveState: LiveState {
        LiveState(speed: gpsSpeed, battery: batteryPercent,
                  distanceKm: activeTrip?.distanceKm ?? 0, rangeKm: remainingRangeKm)
    }

    // MARK: - Status für die Oberfläche

    var isBusy: Bool {
        switch state {
        case .connecting: return !isWaitingForKnownScooter
        case .initializing, .waitingForButtonPress, .pairing: return true
        default: return isScanning || isReading
        }
    }

    var statusText: String {
        switch state {
        case .idle: return isScanning ? "Suche Scooter …" : "Nicht verbunden"
        case .connecting:
            if isWaitingForKnownScooter, let name = connectedName {
                return "Warte auf \(name) — einfach einschalten"
            }
            return "Verbinde …"
        case .initializing: return "Handshake …"
        case .waitingForButtonPress: return "Jetzt den Power-Knopf am Scooter kurz drücken!"
        case .pairing: return "Kopple …"
        case .authenticated: return "Verbunden"
        case .failed(let reason): return "Fehlgeschlagen: \(reason)"
        }
    }

    var locationStatusText: String {
        switch locationStatus {
        case .authorizedAlways: return "Immer"
        case .authorizedWhenInUse: return "Beim Verwenden"
        case .denied, .restricted: return "Nicht erlaubt"
        default: return "Noch nicht gefragt"
        }
    }

    var locationButtonTitle: String? {
        switch locationStatus {
        case .notDetermined: return "Standort erlauben"
        case .authorizedWhenInUse: return "Standort „Immer“ erlauben"
        case .denied, .restricted: return "Einstellungen öffnen"
        default: return nil
        }
    }

    // MARK: - Suchen und Verbinden

    func startScan() {
        scooters = []
        message = nil
        isScanning = true
        scanID += 1
        let id = scanID
        bleManager.startScanning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.scanID == id, self.isScanning else { return }
            self.stopScan()
        }
    }

    private func stopScan() {
        isScanning = false
        bleManager.stopScanning()
    }

    private func add(_ scooter: DiscoveredScooter) {
        if let i = scooters.firstIndex(where: { $0.id == scooter.id }) {
            scooters[i].rssi = scooter.rssi
        } else {
            scooters.append(scooter)
        }
    }

    func connect(to scooter: DiscoveredScooter) {
        stopScan()
        message = nil
        autoPaused = false
        handshakeFailures = 0
        isWaitingForKnownScooter = false
        currentScooter = KnownScooter(id: scooter.id, name: scooter.name)
        connectedName = scooter.name
        session.connect(to: scooter)
    }

    /// Legt einen Verbindungsauftrag für den gemerkten Scooter an.
    private func connectKnownScooter() {
        guard autoConnect, !autoPaused, let known = knownScooter, bleManager.isPoweredOn else { return }
        switch state {
        case .idle, .failed: break
        default: return
        }
        guard let peripheral = bleManager.peripheral(withIdentifier: known.id) else { return }
        currentScooter = known
        connectedName = known.name
        isWaitingForKnownScooter = true
        session.connect(to: DiscoveredScooter(id: known.id, peripheral: peripheral, name: known.name, rssi: 0))
    }

    func disconnect() {
        autoPaused = true   // bis zum nächsten manuellen Verbinden
        session.disconnect()
    }

    func resumeAutoConnect() {
        autoPaused = false
        handshakeFailures = 0
        message = nil
        connectKnownScooter()
    }

    func forgetScooter() {
        knownScooter = nil
        UserDefaults.standard.removeObject(forKey: Keys.knownScooter)
        if state != .authenticated {
            disconnect()
        }
    }

    func requestLocationAccess() {
        if locationStatus == .denied || locationStatus == .restricted {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            location.requestPermission()
        }
    }

    private func remember(_ scooter: KnownScooter) {
        knownScooter = scooter
        if let data = try? JSONEncoder().encode(scooter) {
            UserDefaults.standard.set(data, forKey: Keys.knownScooter)
        }
    }

    private func handle(_ newState: NinebotSessionState) {
        let oldState = state
        state = newState

        switch newState {
        case .initializing:
            isWaitingForKnownScooter = false
            location.start()   // hält die App im Hintergrund wach, bis die Fahrt läuft

        case .authenticated:
            handshakeFailures = 0
            if let scooter = currentScooter { remember(scooter) }
            startTrip()
            startPolling()
            refresh()
            readSettings()

        case .idle, .failed:
            stopPolling()
            finishTrip()
            location.stop()
            isScanning = false
            isReading = false
            isWaitingForKnownScooter = false
            connectedName = nil
            values = []
            liveValues = []
            kersLevel = nil
            cruiseControl = nil
            tailLight = nil

            if case .failed = newState, oldState != .authenticated {
                handshakeFailures += 1
                if handshakeFailures >= 3 && knownScooter != nil && autoConnect {
                    autoPaused = true
                    message = "Automatisches Verbinden pausiert, weil es dreimal nicht geklappt hat."
                }
            }
            // Neuer Auftrag, damit der Scooter beim nächsten Einschalten wieder gefunden wird.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.connectKnownScooter()
            }

        default:
            break
        }
    }

    // MARK: - Werte lesen

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
    }

    private func poll() {
        guard state == .authenticated, !isPolling else { return }
        isPolling = true
        if liveValues.isEmpty {
            liveValues = NinebotRegister.live.map { ScooterValue(id: $0.id, title: $0.title, text: "…") }
        }
        readLive(at: 0)
    }

    private func readLive(at i: Int) {
        let registers = NinebotRegister.live
        guard i < registers.count, state == .authenticated else {
            isPolling = false
            return
        }
        let register = registers[i]
        session.read(register) { [weak self] result in
            guard let self = self else { return }
            if case .success(let data) = result {
                self.set(register.format(data), for: register, in: &self.liveValues)
                self.updateTrip(with: data, from: register)
            }
            self.readLive(at: i + 1)
        }
    }

    func refresh() {
        guard state == .authenticated, !isReading else { return }
        isReading = true
        values = NinebotRegister.overview.map { ScooterValue(id: $0.id, title: $0.title, text: "…") }
        readOverview(at: 0, health: nil)
    }

    private func readOverview(at i: Int, health: Int?) {
        let registers = NinebotRegister.overview
        guard i < registers.count, state == .authenticated else {
            isReading = false
            if i >= registers.count {
                store.addSnapshot(BatterySnapshot(date: Date(), percent: batteryPercent,
                                                  health: health, odometer: odometer))
            }
            return
        }
        let register = registers[i]
        session.read(register) { [weak self] result in
            guard let self = self else { return }
            var health = health
            switch result {
            case .success(let data):
                self.set(register.format(data), for: register, in: &self.values)
                self.applySetting(data, from: register)
                if register.id == NinebotRegister.batteryHealth.id {
                    health = NinebotValue.le16(data)
                }
            case .failure:
                self.set("–", for: register, in: &self.values)
            }
            self.readOverview(at: i + 1, health: health)
        }
    }

    private func set(_ text: String, for register: NinebotRegister, in list: inout [ScooterValue]) {
        if let i = list.firstIndex(where: { $0.id == register.id }) {
            list[i].text = text
        }
    }

    // MARK: - Einstellungen

    private func readSettings() {
        for register in NinebotRegister.settings {
            session.read(register) { [weak self] result in
                if case .success(let data) = result {
                    self?.applySetting(data, from: register)
                }
            }
        }
    }

    private func applySetting(_ data: [UInt8], from register: NinebotRegister) {
        let value = NinebotValue.le16(data)
        switch register.id {
        case NinebotRegister.kers.id:
            kersLevel = value
        case NinebotRegister.cruiseControl.id:
            cruiseControl = value != 0
        case NinebotRegister.tailLight.id:
            tailLight = value != 0
        case NinebotRegister.speedLimit.id:
            set(register.format(data), for: register, in: &values)
            let kmh = (Double(NinebotValue.les16(data)) / 10).rounded()
            if Self.speedLimitRange.contains(kmh) { speedLimit = kmh }
        default:
            break
        }
    }

    func applySpeedLimit() {
        let kmh = min(max(speedLimit, Self.speedLimitRange.lowerBound), Self.speedLimitRange.upperBound)
        write(NinebotRegister.speedLimit, value: Int16(kmh * 10), done: "Tempolimit auf \(Int(kmh)) km/h gesetzt")
    }

    func setKers(_ level: Int) {
        guard (0..<Self.kersLevels.count).contains(level), level != kersLevel else { return }
        write(NinebotRegister.kers, value: Int16(level), done: "Rekuperation: \(Self.kersLevels[level])")
    }

    func setCruiseControl(_ on: Bool) {
        guard on != cruiseControl else { return }
        write(NinebotRegister.cruiseControl, value: on ? 1 : 0, done: "Tempomat \(on ? "an" : "aus")")
    }

    func setTailLight(_ on: Bool) {
        guard on != tailLight else { return }
        write(NinebotRegister.tailLight, value: on ? 1 : 0, done: "Rücklicht \(on ? "an" : "aus")")
    }

    /// Schreibt ein Register und liest es danach zur Kontrolle erneut aus.
    private func write(_ register: NinebotRegister, value: Int16, done: String) {
        message = nil
        session.writeRegister(register.index, value: value) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.message = done
            case .failure(let error):
                self.message = "Fehler beim Schreiben: \(error.localizedDescription)"
            }
            self.session.read(register) { [weak self] result in
                if case .success(let data) = result {
                    self?.applySetting(data, from: register)
                }
            }
        }
    }

    // MARK: - Fahrtenbuch

    private func startTrip() {
        guard activeTrip == nil else { return }
        var trip = Trip(scooterName: currentScooter?.name ?? "Scooter", start: Date())
        trip.weather = weather.flatMap { -$0.time.timeIntervalSinceNow < 30 * 60 ? $0 : nil }
        activeTrip = trip
        location.start()
        liveActivity.start(name: trip.scooterName, start: trip.start, state: liveState)
        refreshWeather(force: false)
    }

    private func updateTrip(with data: [UInt8], from register: NinebotRegister) {
        switch register.id {
        case NinebotRegister.batteryPercent.id:
            let percent = NinebotValue.le16(data)
            batteryPercent = percent
            if activeTrip?.startBattery == nil { activeTrip?.startBattery = percent }
            activeTrip?.endBattery = percent
        case NinebotRegister.totalMileage.id:
            let km = NinebotValue.kilometers(data)
            odometer = km
            maintenance.update(odometer: km)
            if activeTrip?.startOdometer == nil { activeTrip?.startOdometer = km }
            activeTrip?.endOdometer = km
        case NinebotRegister.remainingRange.id:
            remainingRangeKm = Double(NinebotValue.le16(data)) / 100
        default:
            return
        }
        activeTrip?.end = Date()
        liveActivity.update(liveState)
    }

    private func record(_ locations: [CLLocation]) {
        if let last = locations.last {
            gpsSpeed = last.speed >= 0 ? last.speed * 3.6 : nil
        }
        guard var trip = activeTrip else { return }
        locations.forEach { trip.append($0) }
        trip.end = Date()
        activeTrip = trip
        liveActivity.update(liveState)

        if Date().timeIntervalSince(lastActiveSave) > 30 {
            lastActiveSave = Date()
            store.saveActive(trip)
        }
    }

    private func finishTrip() {
        gpsSpeed = nil
        liveActivity.end()
        guard let trip = activeTrip else { return }
        activeTrip = nil
        store.saveActive(nil)
        saveIfRelevant(trip)
    }

    /// Eine Fahrt, die durch einen App-Abbruch nicht abgeschlossen wurde.
    private func finishInterruptedTrip() {
        guard let trip = store.loadActive() else { return }
        store.saveActive(nil)
        saveIfRelevant(trip)
    }

    private func saveIfRelevant(_ trip: Trip) {
        guard trip.duration >= 60, trip.distanceKm >= 0.1 else { return }
        store.add(trip)
        lookUpAddresses(for: trip)
    }

    /// Start- und Zieladresse über Apples Kartendienst ermitteln.
    private func lookUpAddresses(for trip: Trip) {
        guard let first = trip.points.first, let last = trip.points.last else { return }
        geocoder.reverseGeocodeLocation(first.location) { [weak self] placemarks, _ in
            guard let self = self else { return }
            var updated = trip
            updated.startAddress = placemarks?.first.map(Self.describe)
            self.geocoder.reverseGeocodeLocation(last.location) { [weak self] placemarks, _ in
                updated.endAddress = placemarks?.first.map(Self.describe)
                self?.store.update(updated)
            }
        }
    }

    private static func describe(_ placemark: CLPlacemark) -> String {
        let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street, placemark.locality].filter { !($0 ?? "").isEmpty }.compactMap { $0 }.joined(separator: ", ")
    }
}

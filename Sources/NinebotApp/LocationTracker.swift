//
//  LocationTracker.swift
//  GPS-Aufzeichnung für das Fahrtenbuch. Die Positionen bleiben auf dem iPhone.
//

import Foundation
import CoreLocation

final class LocationTracker: NSObject {

    private let manager = CLLocationManager()
    private var isRunning = false
    private var onceHandlers: [(CLLocation?) -> Void] = []

    private(set) var lastLocation: CLLocation?

    var onLocations: (([CLLocation]) -> Void)?
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    /// Erst „Beim Verwenden“, danach „Immer“ (nötig für die Automatik im Hintergrund).
    func requestPermission() {
        switch authorization {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    func start() {
        guard isAuthorized, !isRunning else { return }
        isRunning = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    /// Liefert einmalig die aktuelle Position (höchstens 5 Minuten alt).
    func requestOnce(_ handler: @escaping (CLLocation?) -> Void) {
        if let last = lastLocation, -last.timestamp.timeIntervalSinceNow < 300 {
            handler(last)
            return
        }
        guard isAuthorized else {
            handler(nil)
            return
        }
        onceHandlers.append(handler)
        manager.requestLocation()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }
}

extension LocationTracker: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last ?? lastLocation
        let handlers = onceHandlers
        onceHandlers = []
        handlers.forEach { $0(lastLocation) }
        onLocations?(locations)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Standort nicht verfügbar: \(error.localizedDescription)")
        let handlers = onceHandlers
        onceHandlers = []
        handlers.forEach { $0(nil) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(manager.authorizationStatus)
    }
}

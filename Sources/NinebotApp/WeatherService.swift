//
//  WeatherService.swift
//  Aktuelles Wetter von Open-Meteo (https://open-meteo.com): kostenlos, ohne
//  Konto und ohne API-Schlüssel. Nur aktiv, wenn in der App eingeschaltet.
//  Übertragen wird ausschließlich der auf ca. 1 km gerundete Standort.
//

import Foundation
import CoreLocation

struct WeatherInfo: Codable {
    var time: Date
    var temperature: Double          // °C
    var windSpeed: Double            // km/h
    var windGusts: Double?           // km/h
    var precipitation: Double        // mm in der letzten Stunde
    var rainChance: Int?             // % in den nächsten 2 Stunden (Maximum)
    var code: Int                    // WMO-Wettercode

    var summary: String {
        switch code {
        case 0: return "Klar"
        case 1, 2: return "Leicht bewölkt"
        case 3: return "Bewölkt"
        case 45, 48: return "Nebel"
        case 51, 53, 55, 56, 57: return "Nieselregen"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "Regen"
        case 71, 73, 75, 77, 85, 86: return "Schnee"
        case 95, 96, 99: return "Gewitter"
        default: return "Unbekannt"
        }
    }

    var symbol: String {
        switch code {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55, 56, 57: return "cloud.drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow"
        case 95, 96, 99: return "cloud.bolt.rain"
        default: return "questionmark"
        }
    }

    var shortText: String {
        String(format: "%@, %.0f °C, Wind %.0f km/h", locale: Locale.current, summary, temperature, windSpeed)
    }

    /// Hinweise, die für Scooterfahrer relevant sind.
    var warnings: [String] {
        var result: [String] = []
        if temperature <= 3 { result.append("Glättegefahr möglich") }
        if temperature < 5 { result.append("Kälte verringert die Akkureichweite") }
        if (windGusts ?? windSpeed) >= 40 { result.append("Starke Windböen") }
        if [95, 96, 99].contains(code) { result.append("Gewitter") }
        if let chance = rainChance, chance >= 60 { result.append("Regen wahrscheinlich (\(chance) %)") }
        return result
    }
}

enum WeatherService {

    static func fetch(for coordinate: CLLocationCoordinate2D,
                      completion: @escaping (Result<WeatherInfo, Error>) -> Void) {
        let lat = String(format: "%.2f", coordinate.latitude)
        let lon = String(format: "%.2f", coordinate.longitude)
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,precipitation,weather_code,wind_speed_10m,wind_gusts_10m"
            + "&hourly=precipitation_probability&forecast_hours=2&timezone=auto")!

        URLSession.shared.dataTask(with: url) { data, _, error in
            let result: Result<WeatherInfo, Error>
            if let data = data, let response = try? JSONDecoder().decode(Response.self, from: data) {
                let c = response.current
                result = .success(WeatherInfo(time: Date(), temperature: c.temperature_2m,
                                              windSpeed: c.wind_speed_10m, windGusts: c.wind_gusts_10m,
                                              precipitation: c.precipitation ?? 0,
                                              rainChance: response.hourly?.precipitation_probability.compactMap { $0 }.max(),
                                              code: c.weather_code))
            } else {
                result = .failure(error ?? URLError(.cannotParseResponse))
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let precipitation: Double?
            let weather_code: Int
            let wind_speed_10m: Double
            let wind_gusts_10m: Double?
        }
        struct Hourly: Decodable {
            let precipitation_probability: [Int?]
        }
        let current: Current
        let hourly: Hourly?
    }
}

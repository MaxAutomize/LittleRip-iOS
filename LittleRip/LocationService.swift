@preconcurrency import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestAccess() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func currentLocation() async throws -> CLLocation {
        guard CLLocationManager.locationServicesEnabled() else {
            throw LocationError.servicesDisabled
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            throw LocationError.permissionDenied
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            throw LocationError.permissionDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
                manager.requestLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            if locationContinuation != nil {
                manager.requestLocation()
            }
        case .restricted, .denied:
            finish(with: .failure(LocationError.permissionDenied))
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(LocationError.locationUnavailable))
            return
        }
        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(with: result)
    }
}

enum LocationError: LocalizedError {
    case servicesDisabled
    case permissionDenied
    case locationUnavailable

    var errorDescription: String? {
        switch self {
        case .servicesDisabled: return "Location services are turned off."
        case .permissionDenied: return "LittleRip needs location permission to look up weather near you."
        case .locationUnavailable: return "Your current location is unavailable."
        }
    }
}

enum LiveLookupService {
    static func shouldLookup(prompt: String, history: String) -> Bool {
        if needsWeatherLookup(prompt: prompt, history: history) {
            return true
        }

        let lower = prompt.lowercased()
        let sourceIntents = ["hacker news", "hn top"]
        if sourceIntents.contains(where: lower.contains) { return true }

        let liveIntents = [
            "look up", "search for", "find out", "latest", "current", "right now",
            "today", "tonight", "tomorrow", "recent", "news", "score", "standings",
            "stock", "price", "available", "opening hours", "who won", "what happened"
        ]
        return liveIntents.contains(where: lower.contains) || lower.contains("http://") || lower.contains("https://")
    }

    static func lookupContext(for prompt: String, history: String, locationService: LocationService) async -> String? {
        if prompt.localizedCaseInsensitiveContains("hacker news") || prompt.localizedCaseInsensitiveContains("hn top") {
            return await HackerNewsService.context(for: prompt)
        }

        if needsWeatherLookup(prompt: prompt, history: history) {
            return await weatherContext(for: prompt, locationService: locationService)
        }

        // General web lookup is reserved for requests that need current or explicitly searched information.
        guard shouldLookup(prompt: prompt, history: history) else { return nil }
        return await webContext(for: prompt)
    }

    private static func needsWeatherLookup(prompt: String, history: String) -> Bool {
        let keywords = ["weather", "forecast", "temperature", "rain", "snow", "wind", "humidity"]
        let latestContext = String((history + "\n" + prompt).suffix(1_500)).lowercased()
        return keywords.contains { latestContext.contains($0) }
    }

    private static func weatherContext(for prompt: String, locationService: LocationService) async -> String? {
        let geocoder = CLGeocoder()
        let query = locationQuery(from: prompt)
        let requestedLocation: CLLocation?
        if let query {
            requestedLocation = try? await geocoder.geocodeAddressString(query).first?.location
        } else {
            requestedLocation = nil
        }

        let coordinate: CLLocationCoordinate2D
        if let requestedLocation {
            coordinate = requestedLocation.coordinate
        } else {
            do {
                coordinate = try await locationService.currentLocation().coordinate
            } catch {
                return "Live weather lookup could not use the device location: \(error.localizedDescription)"
            }
        }

        guard let url = URL(string: "https://wttr.in/\(coordinate.latitude),\(coordinate.longitude)?format=j1") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("LittleRip/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let weather = try JSONDecoder().decode(WTTRResponse.self, from: data)
            guard let current = weather.currentCondition.first else { return nil }
            let place = weather.nearestArea.first?.areaName.first?.value ?? (query ?? "your current location")
            let description = current.weatherDesc.first?.value ?? "Unknown conditions"
            return "Fresh live weather lookup for \(place): \(description), \(current.tempF)°F (\(current.tempC)°C), feels like \(current.feelsLikeF)°F, humidity \(current.humidity)%, wind \(current.windspeedMiles) mph."
        } catch {
            return nil
        }
    }

    private static func webContext(for prompt: String) async -> String? {
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_html=1&skip_disambig=1") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let result = try JSONDecoder().decode(DuckDuckGoResponse.self, from: data)
            if let abstract = result.AbstractText, !abstract.isEmpty {
                return "Fresh web lookup result: \(abstract)"
            }
            if let definition = result.Definition, !definition.isEmpty {
                return "Fresh web lookup result: \(definition)"
            }
            return await duckDuckGoLiteContext(for: prompt)
        } catch {
            return await duckDuckGoLiteContext(for: prompt)
        }
    }

    private static func duckDuckGoLiteContext(for prompt: String) async -> String? {
        guard let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://lite.duckduckgo.com/lite/?q=\(encoded)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("LittleRip/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else { return nil }
            let text = html
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "Fresh web-search page for ‘\(prompt)’: \(String(text.prefix(2_000)))"
        } catch {
            return nil
        }
    }

    private static func locationQuery(from prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.split(separator: " ").count <= 4,
           !trimmed.contains("?") && !trimmed.isEmpty {
            return trimmed
        }

        let pattern = "(?:weather|forecast|temperature)\\s+(?:in|for|at)\\s+(.+?)(?:[?.!]|$)"
        guard let match = trimmed.range(of: pattern, options: .regularExpression) else { return nil }
        let text = String(trimmed[match])
        return text.replacingOccurrences(of: "(?:weather|forecast|temperature)\\s+(?:in|for|at)\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WTTRResponse: Decodable {
    let currentCondition: [CurrentCondition]
    let nearestArea: [NearestArea]

    enum CodingKeys: String, CodingKey {
        case currentCondition = "current_condition"
        case nearestArea = "nearest_area"
    }

    struct CurrentCondition: Decodable {
        let tempF: String
        let tempC: String
        let feelsLikeF: String
        let humidity: String
        let windspeedMiles: String
        let weatherDesc: [TextValue]

        enum CodingKeys: String, CodingKey {
            case tempF = "temp_F"
            case tempC = "temp_C"
            case feelsLikeF = "FeelsLikeF"
            case humidity
            case windspeedMiles
            case weatherDesc
        }
    }

    struct NearestArea: Decodable {
        let areaName: [TextValue]

        enum CodingKeys: String, CodingKey {
            case areaName = "areaName"
        }
    }

    struct TextValue: Decodable {
        let value: String

        enum CodingKeys: String, CodingKey {
            case value = "value"
        }
    }
}

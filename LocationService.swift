import Foundation
import CoreLocation
import Observation

/// GPS position plus a reverse-geocoded state, county and place name.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    var authorization: CLAuthorizationStatus = .notDetermined
    var location: CLLocation? = nil
    var stateCode: String? = nil
    var county: String? = nil
    var placeName: String? = nil
    var waterBody: String? = nil
    var countryCode: String? = nil
    var isGeocoding = false

    @ObservationIgnored private var lastGeocoded: CLLocation? = nil

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 75
        authorization = manager.authorizationStatus
        if isAuthorized { manager.startUpdatingLocation() }
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestPermission() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func refresh() {
        lastGeocoded = nil
        if isAuthorized {
            manager.requestLocation()
        }
    }

    /// "Davie, Broward County, FL"
    var summary: String {
        var parts: [String] = []
        if let placeName, !placeName.isEmpty { parts.append(placeName) }
        if let county, !county.isEmpty, county != placeName { parts.append(county) }
        if let stateCode { parts.append(stateCode) }
        return parts.isEmpty ? "Location unknown" : parts.joined(separator: ", ")
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        geocodeIfNeeded(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last known values; the UI lets the user pick a state manually.
    }

    private func geocodeIfNeeded(_ newLocation: CLLocation) {
        if let lastGeocoded, lastGeocoded.distance(from: newLocation) < 800, stateCode != nil { return }
        guard !isGeocoding else { return }
        isGeocoding = true
        lastGeocoded = newLocation
        geocoder.reverseGeocodeLocation(newLocation) { [weak self] placemarks, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isGeocoding = false
                guard let placemark = placemarks?.first else { return }
                self.countryCode = placemark.isoCountryCode
                self.stateCode = StateNames.code(for: placemark.administrativeArea)
                self.county = placemark.subAdministrativeArea
                self.placeName = placemark.locality ?? placemark.name
                self.waterBody = placemark.inlandWater ?? placemark.ocean
            }
        }
    }
}

/// U.S. state name ⇄ postal code.
enum StateNames {
    static let all: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
        "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon",
        "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia",
        "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
        "PR": "Puerto Rico", "VI": "U.S. Virgin Islands",
    ]

    static func code(for administrativeArea: String?) -> String? {
        guard let text = administrativeArea?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let upper = text.uppercased()
        if all[upper] != nil { return upper }
        return all.first { $0.value.caseInsensitiveCompare(text) == .orderedSame }?.key
    }

    static func name(for code: String) -> String {
        all[code] ?? code
    }
}

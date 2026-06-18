#if os(iOS)
import Foundation
import CoreLocation

// MARK: - Location service
//
// Requests when-in-use authorization on first call to `requestLocation()`.
// Exposes the last known coordinate for passing to /list-open.
// Never throws to a dead-end — callers get nil coordinates if location is
// denied or unavailable.

@MainActor
@Observable
final class LocationService: NSObject {

    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var authStatus: CLAuthorizationStatus = .notDetermined

    private let manager: CLLocationManager

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authStatus = manager.authorizationStatus
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    var isAvailable: Bool {
        switch authStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.coordinate = loc.coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location failure is non-fatal — feed falls back to unfiltered list.
    }
}
#endif

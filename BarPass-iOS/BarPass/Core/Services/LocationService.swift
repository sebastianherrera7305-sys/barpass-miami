import CoreLocation

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var onceCompletion: CheckedContinuation<CLLocationCoordinate2D?, Never>?
    var onUpdate: ((Double, Double, Double) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
    }

    func requestOnce() async -> CLLocationCoordinate2D? {
        // Resume any abandoned continuation before creating a new one
        if let existing = onceCompletion {
            onceCompletion = nil
            existing.resume(returning: nil)
        }
        return await withCheckedContinuation { continuation in
            onceCompletion = continuation
            manager.requestWhenInUseAuthorization()
            manager.requestLocation()
        }
    }

    func startUpdating() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        onUpdate?(coord.latitude, coord.longitude, loc.horizontalAccuracy)

        if let cont = onceCompletion {
            onceCompletion = nil
            cont.resume(returning: coord)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("[Location] Error:", error)
        #endif
        if let cont = onceCompletion {
            onceCompletion = nil
            cont.resume(returning: nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            onceCompletion?.resume(returning: nil)
            onceCompletion = nil
        }
    }
}

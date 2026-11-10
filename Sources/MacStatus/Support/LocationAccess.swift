import CoreLocation

/// macOS only reveals the Wi-Fi network name to apps allowed to use Location Services.
/// MacStatus never reads a location: the permission is asked for only when the user clicks "Allow" in the popup,
/// and the name shows up on the next sample once it is granted.
@MainActor
enum LocationAccess {
    private static let manager = CLLocationManager()

    static var status: CLAuthorizationStatus { manager.authorizationStatus }

    static func request() { manager.requestWhenInUseAuthorization() }
}

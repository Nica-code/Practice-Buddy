import DeviceCheck
import FirebaseAppCheck
import FirebaseCore

enum PBAppCheck {
    /// Must run before `FirebaseApp.configure()`. Simulator builds use the
    /// Firebase debug provider; production-capable devices prefer App Attest
    /// and fall back to DeviceCheck when App Attest is unavailable.
    static func configureProviderFactory() {
        #if DEBUG && targetEnvironment(simulator)
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(PBProductionAppCheckProviderFactory())
        #endif
    }
}

private final class PBProductionAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        if DCAppAttestService.shared.isSupported,
           let provider = AppAttestProvider(app: app) {
            return provider
        }
        return DeviceCheckProvider(app: app)
    }
}

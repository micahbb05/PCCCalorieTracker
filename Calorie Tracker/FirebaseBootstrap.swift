import Foundation
#if canImport(FirebaseCore) && canImport(FirebaseAppCheck)
import FirebaseCore
import FirebaseAppCheck

private final class AppCheckBootstrapProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        if #available(iOS 14.0, *) {
            return AppAttestProvider(app: app)
        }
        return DeviceCheckProvider(app: app)
        #endif
    }
}
#endif

enum FirebaseBootstrap {
    static func configureIfAvailable() {
        #if canImport(FirebaseCore) && canImport(FirebaseAppCheck)
        if FirebaseApp.app() != nil { return }
        AppCheck.setAppCheckProviderFactory(AppCheckBootstrapProviderFactory())
        FirebaseApp.configure()
        AppCheck.appCheck().isTokenAutoRefreshEnabled = true
        #endif
    }
}

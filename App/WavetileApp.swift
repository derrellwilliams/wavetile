import Features
import SwiftUI
import UIKit

@main
struct WavetileApp: App {
    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var app: AppModel

    init() {
        // Restore at launch (not on first frame): when iOS relaunches the app in the background
        // to finish downloads, the download session must exist even though no UI is shown.
        let model = AppModel(deviceName: UIDevice.current.name)
        model.restore()
        _app = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        AppModel.handleBackgroundSessionEvents(identifier: identifier, completion: completionHandler)
    }
}

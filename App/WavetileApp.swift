import SwiftUI
import UIKit
import Features

@main
struct WavetileApp: App {
    @State private var app = AppModel(deviceName: UIDevice.current.name)

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
        }
    }
}

import CarPlay
import Features

/// Hands the CarPlay screen to `CarPlayController`, which builds it from the running app's model.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CarPlayController?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        guard let app = AppModel.current else {
            // Never leave the car screen blank.
            let template = CPListTemplate(title: "Wavetile", sections: [])
            template.emptyViewTitleVariants = ["Open Wavetile on your iPhone"]
            interfaceController.setRootTemplate(template, animated: false, completion: nil)
            return
        }
        let controller = CarPlayController(interface: interfaceController, app: app)
        controller.connect()
        self.controller = controller
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        controller?.disconnect()
        controller = nil
    }
}

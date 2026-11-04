import CarPlay
import UIKit

/// Connects the car's screen. The car can launch the app on its own while the phone is locked,
/// so the app hands over its environment at launch rather than through a SwiftUI scene.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    /// Set by the app at launch, before any scene connects.
    static var environment: AppEnvironment?
    private var controller: CarPlayController?

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        guard let environment = Self.environment else { return }
        let controller = CarPlayController(environment: environment, interface: interfaceController)
        controller.connect()
        self.controller = controller
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        controller?.disconnect()
        controller = nil
    }
}

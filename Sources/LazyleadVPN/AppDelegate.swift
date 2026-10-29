import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MenuController?
    private var vpnController: VPNController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }

        let logStore = LogStore()
        let vpnController = VPNController(logStore: logStore)
        let menuController = MenuController(vpnController: vpnController, logStore: logStore)

        vpnController.onStateChange = { [weak menuController] state in
            DispatchQueue.main.async {
                menuController?.render(state: state)
            }
        }
        vpnController.onSAMLURLChange = { [weak menuController, weak vpnController] in
            DispatchQueue.main.async {
                guard let vpnController else { return }
                menuController?.render(state: vpnController.state)
            }
        }

        self.vpnController = vpnController
        self.menuController = menuController
        menuController.render(state: vpnController.state)
        vpnController.refreshDirectState()
        if CommandLine.arguments.contains("--show-routes") || !UserDefaults.standard.bool(forKey: "hasShownRoutingOverview") {
            menuController.openRoutes()
            UserDefaults.standard.set(true, forKey: "hasShownRoutingOverview")
        }
    }
}

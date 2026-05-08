import AppKit
import LazyleadVPNCore

final class MenuController: NSObject {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let vpnController: VPNController
    private let logStore: LogStore
    private var infoWindowController: InfoWindowController?

    private let connectMenuItem = NSMenuItem(title: "Connect", action: #selector(connect), keyEquivalent: "")
    private let disconnectMenuItem = NSMenuItem(title: "Disconnect", action: #selector(disconnect), keyEquivalent: "")
    private let settingsMenuItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")

    init(vpnController: VPNController, logStore: LogStore) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu(title: "Lazylead VPN")
        self.vpnController = vpnController
        self.logStore = logStore

        super.init()

        configureStatusItem()
        configureMenu()
    }

    func render(state: VPNState) {
        connectMenuItem.isEnabled = state.canConnect
        disconnectMenuItem.isEnabled = state.canDisconnect
        statusItem.button?.image = CatStatusIcon.makeImage(active: state.usesActiveIcon)
        statusItem.button?.toolTip = state.errorMessage ?? state.menuTitle
    }

    private func configureStatusItem() {
        statusItem.button?.image = CatStatusIcon.makeImage(active: false)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.menu = menu
    }

    private func configureMenu() {
        connectMenuItem.target = self
        disconnectMenuItem.target = self
        settingsMenuItem.target = self

        menu.addItem(connectMenuItem)
        menu.addItem(disconnectMenuItem)
        menu.addItem(settingsMenuItem)
    }

    @objc private func connect() {
        vpnController.connect()
    }

    @objc private func disconnect() {
        vpnController.disconnect()
    }

    @objc private func openSettings() {
        if infoWindowController == nil {
            infoWindowController = InfoWindowController(
                infoProvider: InfoProvider(vpnController: vpnController, logStore: logStore),
                vpnController: vpnController,
                logStore: logStore
            )
        }
        infoWindowController?.show()
    }
}

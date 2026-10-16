import AppKit

final class InfoWindowController: NSWindowController {
    private let infoProvider: InfoProvider
    private let vpnController: VPNController
    private let logStore: LogStore
    private let showRoutes: () -> Void
    private let fieldsStack = NSStackView()
    private let routingTextView = NSTextView()
    private let open2FAButton = NSButton(title: "Open 2FA Page", target: nil, action: nil)

    init(infoProvider: InfoProvider, vpnController: VPNController, logStore: LogStore, showRoutes: @escaping () -> Void = {}) {
        self.infoProvider = infoProvider
        self.vpnController = vpnController
        self.logStore = logStore
        self.showRoutes = showRoutes

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lazylead VPN Settings"
        window.minSize = NSSize(width: 760, height: 540)

        super.init(window: window)

        buildContent()
        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        refresh()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        let title = NSTextField(labelWithString: "Lazylead VPN Settings")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        root.addArrangedSubview(title)

        let buttonStack = NSStackView()
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.alignment = .centerY
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshAction))
        let openLimaButton = NSButton(title: "Open Lima Folder", target: self, action: #selector(openLimaFolder))
        let openScriptsButton = NSButton(title: "Open Scripts Folder", target: self, action: #selector(openScriptsFolder))
        let openLogButton = NSButton(title: "Open Log", target: self, action: #selector(openLog))
        open2FAButton.target = self
        open2FAButton.action = #selector(open2FAPage)
        let quitButton = NSButton(title: "Quit App", target: self, action: #selector(quitApp))

        [refreshButton, open2FAButton, openLimaButton, openScriptsButton, openLogButton, quitButton].forEach {
            buttonStack.addArrangedSubview($0)
        }
        buttonStack.addArrangedSubview(NSView())
        root.addArrangedSubview(buttonStack)
        buttonStack.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        fieldsStack.orientation = .vertical
        fieldsStack.alignment = .leading
        fieldsStack.spacing = 7
        fieldsStack.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(fieldsStack)
        fieldsStack.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let routingLabel = NSTextField(labelWithString: "Routing Table")
        routingLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let routingHeader = NSStackView(views: [routingLabel, NSView(),
            NSButton(title: "Traffic & Routes…", target: self, action: #selector(openRoutes))])
        root.addArrangedSubview(routingHeader)
        routingHeader.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        routingTextView.isEditable = false
        routingTextView.isSelectable = true
        routingTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        routingTextView.textContainerInset = NSSize(width: 10, height: 10)
        routingTextView.minSize = NSSize(width: 0, height: 0)
        routingTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        routingTextView.isHorizontallyResizable = true
        routingTextView.isVerticallyResizable = true
        routingTextView.textContainer?.widthTracksTextView = false

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.documentView = routingTextView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 330)
        ])
    }

    private func refresh() {
        let snapshot = infoProvider.makeSnapshot()
        render(snapshot)
    }

    private func render(_ snapshot: InfoSnapshot) {
        fieldsStack.arrangedSubviews.forEach {
            fieldsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        addField("App Version", snapshot.appVersion)
        addField("Network Mode", vpnController.usesDirectNetworking ? "Direct via provider (no Check Point)" : "Check Point")
        addField("limactl", "\(snapshot.limactlVersion) (\(snapshot.limactlPath))")
        addField("VM", "\(snapshot.vmName): \(snapshot.vmStatus)")
        addField("Lima Instance", snapshot.limaInstanceDirectory)
        addField("Lima Disk", "\(snapshot.limaDiskPath) (\(snapshot.limaDiskSize))")
        addField("Lima Config", snapshot.limaConfigPath)
        addField("Scripts", snapshot.scriptsDirectory)
        addField("Privileged Scripts", snapshot.privilegedScriptsDirectory)
        addField("sudoers", "\(snapshot.sudoersStatus): \(snapshot.sudoersPath)")
        addField("Log", snapshot.logPath)

        routingTextView.string = snapshot.routingTable
        open2FAButton.isEnabled = vpnController.lastSAMLURL != nil
    }

    private func addField(_ name: String, _ value: String) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let valueField = NSTextField(labelWithString: value)
        valueField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        valueField.alignment = .left
        valueField.lineBreakMode = .byTruncatingMiddle
        valueField.maximumNumberOfLines = 1
        valueField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(label)
        row.addArrangedSubview(valueField)
        fieldsStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: fieldsStack.widthAnchor).isActive = true
    }

    @objc private func refreshAction() {
        refresh()
    }

    @objc private func openRoutes() { showRoutes() }

    @objc private func open2FAPage() {
        vpnController.openLastSAMLURL()
    }

    @objc private func openLimaFolder() {
        let snapshot = infoProvider.makeSnapshot()
        NSWorkspace.shared.open(URL(fileURLWithPath: snapshot.limaInstanceDirectory))
    }

    @objc private func openScriptsFolder() {
        let snapshot = infoProvider.makeSnapshot()
        NSWorkspace.shared.open(URL(fileURLWithPath: snapshot.scriptsDirectory))
    }

    @objc private func openLog() {
        NSWorkspace.shared.activateFileViewerSelecting([logStore.fileURL])
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

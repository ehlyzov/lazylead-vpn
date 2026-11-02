import AppKit
import LazyleadVPNCore

final class NetworkWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let vpn: VPNController
    private let table = NSTableView()
    private let kind = NSPopUpButton()
    private let destination = NSTextField()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let vmStatus = NSTextField(wrappingLabelWithString: "")
    private let add = NSButton(title: "Add rule…", target: nil, action: nil)
    private let remove = NSButton(title: "Remove selected…", target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let restart = NSButton(title: "Restart Lima", target: nil, action: nil)
    private let repair = NSButton(title: "Repair network…", target: nil, action: nil)
    private let startStop = NSButton(title: "Start Lima", target: nil, action: nil)
    private var rows: [(RoutingRuleKind, String)] = []
    private var busy = false
    private var loading = false

    init(vpnController: VPNController) {
        vpn = vpnController
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 670),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Network & Routes"
        window.minSize = NSSize(width: 740, height: 620)
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        render(state: vpn.state)
        reload()
    }

    func render(state: VPNState) {
        vmStatus.stringValue = state.errorMessage ?? "Lima: \(state.label)"
        startStop.title = state.canConnect ? "Start Lima" : "Stop Lima"
        updateControls()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 13
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])
        let title = NSTextField(labelWithString: "Network & Routes")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        root.addArrangedSubview(title)
        vmStatus.font = .systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(vmStatus)
        let networkButtons = NSStackView(views: [startStop, restart, repair])
        networkButtons.spacing = 10
        root.addArrangedSubview(networkButtons)
        startStop.target = self; startStop.action = #selector(toggleLima)
        restart.target = self; restart.action = #selector(restartLima)
        repair.target = self; repair.action = #selector(repairNetwork)
        let repairNote = NSTextField(wrappingLabelWithString:
            "Repair network gracefully stops Lima, restarts its network bridge, then starts Lima again. Downloads pause briefly. macOS asks for administrator authorization; cancelling leaves Lima stopped.")
        repairNote.font = .systemFont(ofSize: 11)
        repairNote.textColor = .secondaryLabelColor
        root.addArrangedSubview(repairNote)
        let heading = NSTextField(labelWithString: "Destinations through Lima")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        root.addArrangedSubview(heading)
        let explanation = NSTextField(wrappingLabelWithString:
            "Domains include all subdomains. IPv4 addresses and CIDR networks are also supported. Other destinations use the normal macOS route. Yandex Cloud's installed address snapshot is shown in Traffic & Routes.")
        explanation.font = .systemFont(ofSize: 12)
        root.addArrangedSubview(explanation)
        for (identifier, title, width) in [("kind", "Rule", 180.0), ("destination", "Destination", 470.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = 150
            table.addTableColumn(column)
        }
        table.delegate = self
        table.dataSource = self
        table.rowHeight = 27
        table.usesAlternatingRowBackgroundColors = true
        table.allowsEmptySelection = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        kind.addItems(withTitles: RoutingRuleKind.allCases.map(\.title))
        kind.target = self; kind.action = #selector(changeKind)
        kind.widthAnchor.constraint(equalToConstant: 195).isActive = true
        destination.placeholderString = "example.com or .ru"
        destination.setAccessibilityLabel("Routing destination")
        destination.target = self; destination.action = #selector(addRule)
        destination.setContentHuggingPriority(.defaultLow, for: .horizontal)
        add.target = self; add.action = #selector(addRule)
        let entry = NSStackView(views: [kind, destination, add])
        entry.spacing = 10
        root.addArrangedSubview(entry)
        remove.target = self; remove.action = #selector(removeRule)
        refreshButton.target = self; refreshButton.action = #selector(reload)
        let footer = NSStackView(views: [remove, NSView(), refreshButton])
        footer.spacing = 10
        root.addArrangedSubview(footer)
        message.font = .systemFont(ofSize: 12)
        message.isSelectable = true
        message.maximumNumberOfLines = 4
        message.stringValue = "Changes are saved on this Mac and require administrator authorization."
        root.addArrangedSubview(message)
        let note = NSTextField(wrappingLabelWithString:
            "Domain routing uses IPv4 and system DNS. Shared IPs or addresses learned before this update can remain through Lima until their DNS route leases expire. Existing browser connections may need a reload after a change.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)
        for view in [vmStatus, repairNote, explanation, scroll, entry, footer, message, note] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }

    @objc private func changeKind() {
        destination.placeholderString = kind.indexOfSelectedItem == 0 ? "example.com or .ru" : "8.8.8.8 or 8.8.8.0/24"
    }

    @objc private func reload() {
        guard !busy, !loading else { return }
        loading = true
        updateControls()
        vpn.readManagedRules { [weak self] result in
            guard let self else { return }
            self.loading = false
            switch result {
            case let .success(rules):
                self.rows = rules.domains.map { (.domain, $0) } + rules.networks.map { (.network, $0) }
                self.table.reloadData()
            case let .failure(error):
                self.message.stringValue = error.localizedDescription
                self.message.textColor = .systemRed
            }
            self.updateControls()
        }
    }

    private func updateControls() {
        let enabled = !busy && !loading && vpn.usesDirectNetworking && vpn.vmGateway == "192.168.64.2"
        let transitioning = !vpn.state.canConnect && vpn.state != .connected
        add.isEnabled = enabled && !transitioning
        remove.isEnabled = enabled && !transitioning && rows.indices.contains(table.selectedRow)
        restart.isEnabled = enabled && !transitioning
        repair.isEnabled = enabled && !transitioning
        startStop.isEnabled = enabled && !transitioning
        refreshButton.isEnabled = !busy && !loading
        destination.isEnabled = enabled
        kind.isEnabled = enabled
    }

    private func begin(_ text: String) {
        busy = true
        message.textColor = .secondaryLabelColor
        message.stringValue = text
        updateControls()
    }

    private func finish(_ result: Result<String, Error>) {
        busy = false
        switch result {
        case let .success(text):
            message.stringValue = text
            message.textColor = .labelColor
        case let .failure(error):
            message.stringValue = error.localizedDescription
            message.textColor = .systemRed
        }
        render(state: vpn.state)
        reload()
    }

    @objc private func toggleLima() {
        if vpn.state.canConnect { vpn.connect() } else { vpn.disconnect() }
    }

    @objc private func restartLima() { recover(repair: false) }
    @objc private func repairNetwork() { recover(repair: true) }
    private func recover(repair: Bool) {
        begin(repair ? "Stopping Lima, then requesting authorization to repair its network…" : "Restarting Lima…")
        vpn.restartDirectNetwork(repairBridge: repair) { [weak self] result in self?.finish(result) }
    }

    @objc private func addRule() {
        guard add.isEnabled else { return }
        let selected = RoutingRuleKind.allCases[kind.indexOfSelectedItem]
        do {
            let value = try selected.normalize(destination.stringValue)
            begin("Requesting administrator authorization to add \(value)…")
            vpn.changeRoutingRule(kind: selected, value: value, remove: false) { [weak self] result in
                if case .success = result { self?.destination.stringValue = "" }
                self?.finish(result)
            }
        } catch {
            message.stringValue = error.localizedDescription
            message.textColor = .systemRed
        }
    }

    @objc private func removeRule() {
        guard rows.indices.contains(table.selectedRow) else { return }
        let (kind, value) = rows[table.selectedRow]
        begin("Requesting administrator authorization to remove \(value)…")
        vpn.changeRoutingRule(kind: kind, value: value, remove: true) { [weak self] result in self?.finish(result) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateControls() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let (kind, value) = rows[row]
        let text = tableColumn?.identifier.rawValue == "kind" ? kind.title : (value == "xn--p1ai" ? ".рф" : value)
        let field = NSTextField(labelWithString: text)
        field.font = tableColumn?.identifier.rawValue == "kind" ? .systemFont(ofSize: 12) : .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

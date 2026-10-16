import AppKit
import LazyleadVPNCore

final class RoutesWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let provider: RoutingInfoProvider
    private let subtitle = NSTextField(wrappingLabelWithString: "Reading installed routing rules…")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let domains = NSTextField(wrappingLabelWithString: "Loading…")
    private let cloud = NSTextField(wrappingLabelWithString: "Loading…")
    private let transmission = NSTextField(wrappingLabelWithString: "Loading…")
    private let otherTraffic = NSTextField(wrappingLabelWithString: "Loading…")
    private let count = NSTextField(labelWithString: "Installed IPv4 routes")
    private let updated = NSTextField(labelWithString: "")
    private let search = NSSearchField()
    private let table = NSTableView()
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let copyButton = NSButton(title: "Copy routes", target: nil, action: nil)
    private var snapshot: RoutingSnapshot?
    private var visibleRoutes: [SystemRoute] = []
    private var refreshing = false

    init(vmName: String, gateway: String, direct: Bool) {
        provider = RoutingInfoProvider(vmName: vmName, gateway: gateway, direct: direct)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Traffic through Lima"
        window.minSize = NSSize(width: 780, height: 700)
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18)
        ])
        let title = NSTextField(labelWithString: "Traffic through Lima")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        root.addArrangedSubview(title)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitle)
        status.font = .systemFont(ofSize: 13, weight: .medium)
        root.addArrangedSubview(status)

        let box = NSBox()
        box.boxType = .custom
        box.fillColor = .controlBackgroundColor
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.cornerRadius = 10
        box.contentViewMargins = NSSize(width: 16, height: 14)
        let summaries = NSStackView()
        summaries.orientation = .vertical
        summaries.alignment = .leading
        summaries.spacing = 14
        for (symbol, title, field) in [
            ("globe", "Domains", domains), ("cloud", "Yandex Cloud", cloud),
            ("arrow.down.circle", "Transmission", transmission), ("arrow.triangle.branch", "Other Mac traffic", otherTraffic)
        ] {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 12
            let image = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage())
            image.contentTintColor = .secondaryLabelColor
            image.widthAnchor.constraint(equalToConstant: 20).isActive = true
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.widthAnchor.constraint(equalToConstant: 118).isActive = true
            field.font = .systemFont(ofSize: 12)
            field.isSelectable = true
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(image)
            row.addArrangedSubview(label)
            row.addArrangedSubview(field)
            summaries.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: summaries.widthAnchor).isActive = true
        }
        box.contentView = summaries
        root.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 10
        count.font = .systemFont(ofSize: 13, weight: .semibold)
        controls.addArrangedSubview(count)
        controls.addArrangedSubview(NSView())
        search.placeholderString = "Find an IP, network, or interface"
        search.delegate = self
        search.widthAnchor.constraint(equalToConstant: 260).isActive = true
        controls.addArrangedSubview(search)
        root.addArrangedSubview(controls)
        controls.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        for (identifier, title, width) in [("destination", "IPv4 destination", 255.0), ("gateway", "Gateway", 170.0),
                                           ("interface", "Interface", 145.0), ("scope", "Scope", 100.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = 90
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 25
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        root.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        let footer = NSStackView()
        footer.spacing = 10
        updated.font = .systemFont(ofSize: 11)
        updated.textColor = .secondaryLabelColor
        footer.addArrangedSubview(updated)
        footer.addArrangedSubview(NSView())
        copyButton.target = self
        copyButton.action = #selector(copyRoutes)
        copyButton.toolTip = "Copy all routes currently shown in the filtered list."
        copyButton.isEnabled = false
        refreshButton.target = self
        refreshButton.action = #selector(refresh)
        footer.addArrangedSubview(copyButton)
        footer.addArrangedSubview(refreshButton)
        root.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let note = NSTextField(wrappingLabelWithString:
            "IPv4 configuration, not a live traffic monitor. More-specific routes can override prefixes; shared IPs and custom DNS can affect the actual path.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        root.addArrangedSubview(note)
        for view in [subtitle, status, note] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }

    @objc private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        refreshButton.isEnabled = false
        updated.stringValue = "Refreshing…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let value = self.provider.snapshot()
            DispatchQueue.main.async {
                self.snapshot = value
                self.render(value)
                self.refreshing = false
                self.refreshButton.isEnabled = true
            }
        }
    }

    private func render(_ value: RoutingSnapshot) {
        subtitle.stringValue = "\(value.mode) · VM: \(value.vmName) · Lima gateway: \(value.gateway)"
        let running = value.vmStatus.lowercased() == "running"
        status.stringValue = running
            ? "VM running — rules below show the configured destinations."
            : "VM \(value.vmStatus.lowercased()) — installed rules may remain, but traffic needs a running VM."
        status.textColor = running ? .labelColor : .systemOrange
        if !value.resolversAvailable {
            domains.stringValue = "DNS configuration could not be read."
        } else if value.dnsRules.isEmpty {
            domains.stringValue = "No DNS rules through Lima detected. IP routes below may still apply."
        } else {
            let names = value.dnsRules.map(\.displayDomain).joined(separator: ", ")
            let service = value.dnsRules.contains(where: \.usesLocalProxy)
                ? (value.dnsServiceRunning == true ? " Local DNS service is running; it adds IP routes as names resolve." : " Local DNS service status is unavailable or stopped.")
                : " DNS servers use installed routes through Lima."
            domains.stringValue = "\(names) and all their subdomains.\(service)"
        }
        if let networks = value.cloudNetworks, !networks.isEmpty {
            cloud.stringValue = value.tableAvailable
                ? "\(value.cloudRouteCount) matching routes · snapshot: \(networks.count) IPv4 ranges (overlaps included). API, console, storage and CDN."
                : "Snapshot: \(networks.count) IPv4 ranges. The installed routing table could not be read."
        } else {
            cloud.stringValue = "Installed address snapshot unavailable. Check the exact IP routes below."
        }
        if !running {
            transmission.stringValue = "Unavailable while this VM is stopped."
        } else if value.transmission == "active" {
            let direct = value.guestDefault.map { defaults in
                let lines = defaults.split(separator: "\n")
                return !lines.isEmpty && lines.allSatisfy { $0.contains(" dev direct0 ") || $0.hasSuffix(" dev direct0") }
            } ?? false
            transmission.stringValue = direct ? "Daemon running inside Lima · default IPv4 path: provider."
                : "Daemon running inside Lima; provider uplink could not be confirmed."
        } else {
            transmission.stringValue = value.transmission == nil ? "Guest service status unavailable." : "Daemon is not running in this VM."
        }
        otherTraffic.stringValue = value.table.defaultInterface.map { "Uses the macOS default route (\($0)). More-specific routes can override it." }
            ?? "macOS default route unavailable."
        updated.stringValue = "Updated \(DateFormatter.localizedString(from: value.date, dateStyle: .none, timeStyle: .medium))"
        filterRoutes()
    }

    func controlTextDidChange(_ notification: Notification) { filterRoutes() }

    private func filterRoutes() {
        visibleRoutes = snapshot?.limaRoutes.filter { $0.matches(search.stringValue) } ?? []
        let total = snapshot?.limaRoutes.count ?? 0
        count.stringValue = snapshot?.tableAvailable == false ? "Routing table unavailable"
            : "IPv4 routes · \(visibleRoutes.count) of \(total)"
        copyButton.isEnabled = !visibleRoutes.isEmpty
        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleRoutes.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let route = visibleRoutes[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "destination": text = route.network.description
        case "gateway": text = route.gateway
        case "interface": text = route.interface
        default: text = route.isScoped ? "Interface only" : "Global"
        }
        let field = NSTextField(labelWithString: text)
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    @objc private func copyRoutes() {
        let text = (["IPv4 destination\tGateway\tInterface\tScope"] + visibleRoutes.map {
            "\($0.network.description)\t\($0.gateway)\t\($0.interface)\t\($0.isScoped ? "Interface only" : "Global")"
        }).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

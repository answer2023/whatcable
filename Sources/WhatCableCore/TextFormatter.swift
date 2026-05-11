import Foundation

public enum TextFormatter {
    public static func render(
        ports: [USBCPort],
        sources: [PowerSource],
        identities: [PDIdentity],
        showRaw: Bool,
        adapter: AdapterInfo? = nil,
        thunderboltSwitches: [ThunderboltSwitch] = [],
        isDesktopMac: Bool = false,
        federatedIdentities: [FederatedIdentity] = []
    ) -> String {
        if ports.isEmpty {
            return String(localized: "No USB-C / MagSafe ports were found on this Mac.", bundle: .module) + "\n"
        }

        var out = ""
        if isDesktopMac {
            out += ANSI.wrap(ANSI.dim, String(localized: "Desktop Mac: charger identity (FedDetails) is not available (no battery controller).", bundle: .module)) + "\n\n"
        }
        for (i, port) in ports.enumerated() {
            if i > 0 { out += "\n" }
            out += renderPort(
                port,
                sources: filterSources(port, all: sources),
                identities: filterIdentities(port, all: identities),
                showRaw: showRaw,
                adapter: adapter,
                thunderboltSwitches: thunderboltSwitches,
                federatedIdentities: federatedIdentities
            )
        }
        return out
    }

    private static func renderPort(
        _ port: USBCPort,
        sources: [PowerSource],
        identities: [PDIdentity],
        showRaw: Bool,
        adapter: AdapterInfo?,
        thunderboltSwitches: [ThunderboltSwitch],
        federatedIdentities: [FederatedIdentity] = []
    ) -> String {
        let summary = PortSummary(
            port: port,
            sources: sources,
            identities: identities,
            thunderboltSwitches: thunderboltSwitches,
            federatedIdentities: federatedIdentities
        )
        let label = port.portDescription ?? port.serviceName
        let typeSuffix = port.portTypeDescription.map { " (\($0))" } ?? ""

        let header = "=== \(label)\(typeSuffix) ==="
        var out = ANSI.wrap(ANSI.bold + ANSI.cyan, header) + "\n"

        let headlineColor = color(for: summary.status)
        out += ANSI.wrap(ANSI.bold + headlineColor, summary.headline) + "\n"
        out += ANSI.wrap(ANSI.dim, summary.subtitle) + "\n"

        if !summary.bullets.isEmpty {
            out += "\n"
            for bullet in summary.bullets {
                out += "  " + ANSI.wrap(ANSI.gray, "•") + " \(bullet)\n"
            }
        }

        if let diag = ChargingDiagnostic(port: port, sources: sources, identities: identities, adapter: adapter) {
            let diagColor = diag.isWarning ? ANSI.yellow : ANSI.green
            out += "\n" + ANSI.wrap(ANSI.bold, String(localized: "Charging: ", bundle: .module)) + ANSI.wrap(diagColor, diag.summary) + "\n"
            out += "  " + ANSI.wrap(ANSI.dim, diag.detail) + "\n"
        }

        // Cable trust signals: hedged flags raised against the e-marker.
        // Match the popover's behaviour: only render when at least one flag
        // fires, and use the same titles + details so wording stays
        // consistent across surfaces.
        if let cable = identities.first(where: { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }) {
            let trust = CableTrustReport(identity: cable)
            if !trust.isEmpty {
                out += "\n" + ANSI.wrap(ANSI.bold + ANSI.yellow, String(localized: "Cable trust signals:", bundle: .module)) + "\n"
                for flag in trust.flags {
                    out += "  " + ANSI.wrap(ANSI.yellow, "⚠") + " " + ANSI.wrap(ANSI.bold, flag.title) + "\n"
                    out += "    " + ANSI.wrap(ANSI.dim, flag.detail) + "\n"
                }
            }
        }

        if showRaw {
            if let cable = identities.first(where: {
                $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime
            }), let v2 = cable.activeCableVDO2 {
                out += "\n" + ANSI.wrap(ANSI.bold, String(localized: "Active cable (VDO 2):", bundle: .module)) + "\n"
                out += rawRow(String(localized: "Physical connection", bundle: .module), v2.physicalConnection.label)
                out += rawRow(String(localized: "Active element", bundle: .module), v2.activeElement.label)
                out += rawRow(String(localized: "Optically isolated", bundle: .module), yesNo(v2.opticallyIsolated))
                out += rawRow(String(localized: "USB lanes", bundle: .module), v2.twoLanesSupported ? String(localized: "Two", bundle: .module) : String(localized: "One", bundle: .module))
                out += rawRow(String(localized: "USB Gen", bundle: .module), v2.usbGen2OrHigher ? String(localized: "Gen 2 or higher", bundle: .module) : String(localized: "Gen 1", bundle: .module))
                out += rawRow(String(localized: "USB4 supported", bundle: .module), yesNo(v2.usb4Supported))
                out += rawRow(String(localized: "USB 3.2 supported", bundle: .module), yesNo(v2.usb32Supported))
                out += rawRow(String(localized: "USB 2.0 supported", bundle: .module), yesNo(v2.usb2Supported))
                out += rawRow(String(localized: "USB 2.0 hub hops", bundle: .module), String(v2.usb2HubHopsConsumed))
                out += rawRow(String(localized: "USB4 asymmetric", bundle: .module), yesNo(v2.usb4AsymmetricMode))
                out += rawRow(String(localized: "U3 to U0 transition", bundle: .module), v2.u3ToU0TransitionThroughU3S ? String(localized: "Through U3S", bundle: .module) : String(localized: "Direct", bundle: .module))
                out += rawRow(String(localized: "Idle power (U3/CLd)", bundle: .module), v2.u3CLdPower.label)
                out += rawRow(String(localized: "Max operating temp", bundle: .module), tempLabel(v2.maxOperatingTempC))
                out += rawRow(String(localized: "Shutdown temp", bundle: .module), tempLabel(v2.shutdownTempC))
            }

            out += "\n" + ANSI.wrap(ANSI.bold, String(localized: "Raw IOKit properties:", bundle: .module)) + "\n"
            for key in port.rawProperties.keys.sorted() {
                let value = port.rawProperties[key] ?? ""
                out += "  " + ANSI.wrap(ANSI.gray, key) + " = \(value)\n"
            }
        }

        return out
    }

    private static func rawRow(_ key: String, _ value: String) -> String {
        "  " + ANSI.wrap(ANSI.gray, key) + " = \(value)\n"
    }

    private static func yesNo(_ v: Bool) -> String { v ? String(localized: "Yes", bundle: .module) : String(localized: "No", bundle: .module) }

    /// 0 in the temperature fields means "not specified" per the spec.
    private static func tempLabel(_ v: Int) -> String {
        v == 0 ? "—" : "\(v)°C"
    }

    private static func color(for status: PortSummary.Status) -> String {
        switch status {
        case .empty: return ANSI.gray
        case .charging: return ANSI.yellow
        case .dataDevice: return ANSI.blue
        case .thunderboltCable: return ANSI.magenta
        case .displayCable: return ANSI.cyan
        case .unknown: return ANSI.yellow
        }
    }

    private static func filterSources(_ port: USBCPort, all: [PowerSource]) -> [PowerSource] {
        guard let key = port.portKey else { return [] }
        return all.filter { $0.portKey == key }
    }

    private static func filterIdentities(_ port: USBCPort, all: [PDIdentity]) -> [PDIdentity] {
        guard let key = port.portKey else { return [] }
        return all.filter { $0.portKey == key }
    }
}

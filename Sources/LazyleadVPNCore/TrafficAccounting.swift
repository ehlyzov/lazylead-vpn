import Foundation

public struct TrafficBytes: Codable, Equatable {
    public let received: UInt64
    public let sent: UInt64

    public init(received: UInt64, sent: UInt64) {
        self.received = received
        self.sent = sent
    }
}

public struct TrafficReading: Codable, Equatable {
    public let epoch: String
    public let interface: String
    public let bytes: TrafficBytes

    public init(epoch: String, interface: String, bytes: TrafficBytes) {
        self.epoch = epoch
        self.interface = interface
        self.bytes = bytes
    }
}

public struct TrafficSample: Codable, Equatable {
    public let date: Date
    public let uplink: TrafficReading
    public let macLink: TrafficReading

    public init(date: Date, uplink: TrafficReading, macLink: TrafficReading) {
        self.date = date
        self.uplink = uplink
        self.macLink = macLink
    }
}

public struct TrafficRate: Equatable {
    public let received: Double
    public let sent: Double
}

public struct TrafficUpdate {
    public let uplinkRate: TrafficRate?
    public let macLinkRate: TrafficRate?
}

/// Interface byte counters, rather than packet counts or sums of overlapping links.
public struct TrafficLedger: Codable, Equatable {
    public private(set) var started: Date
    public private(set) var last: TrafficSample
    public private(set) var uplink = TrafficBytes(received: 0, sent: 0)
    public private(set) var macLink = TrafficBytes(received: 0, sent: 0)
    public private(set) var discontinuities = 0

    public init(baseline: TrafficSample) {
        started = baseline.date
        last = baseline
    }

    public mutating func record(_ sample: TrafficSample) -> TrafficUpdate {
        guard sample.date > last.date else { return TrafficUpdate(uplinkRate: nil, macLinkRate: nil) }
        let interval = sample.date.timeIntervalSince(last.date)
        let internet = Self.delta(previous: last.uplink, current: sample.uplink)
        let link = Self.delta(previous: last.macLink, current: sample.macLink)
        if internet.reset || link.reset { discontinuities += 1 }
        uplink = Self.add(uplink, internet.bytes)
        macLink = Self.add(macLink, link.bytes)
        last = sample
        // A long gap is useful for totals but does not describe the current speed.
        func rate(_ delta: (bytes: TrafficBytes, reset: Bool)) -> TrafficRate? {
            guard !delta.reset, interval <= 30 else { return nil }
            return TrafficRate(received: Double(delta.bytes.received) / interval,
                               sent: Double(delta.bytes.sent) / interval)
        }
        return TrafficUpdate(uplinkRate: rate(internet), macLinkRate: rate(link))
    }

    private static func delta(previous: TrafficReading, current: TrafficReading) -> (bytes: TrafficBytes, reset: Bool) {
        if previous.epoch != current.epoch {
            // A new boot/interface has a fresh zero origin. Only its observed bytes
            // are recoverable; unobserved traffic before the restart is unknown.
            return (current.bytes, true)
        }
        let reset = current.bytes.received < previous.bytes.received || current.bytes.sent < previous.bytes.sent
        if reset {
            return (TrafficBytes(received: current.bytes.received < previous.bytes.received
                                 ? current.bytes.received : current.bytes.received - previous.bytes.received,
                                 sent: current.bytes.sent < previous.bytes.sent
                                 ? current.bytes.sent : current.bytes.sent - previous.bytes.sent), true)
        }
        return (TrafficBytes(received: current.bytes.received - previous.bytes.received,
                             sent: current.bytes.sent - previous.bytes.sent), false)
    }

    private static func add(_ left: TrafficBytes, _ right: TrafficBytes) -> TrafficBytes {
        func saturated(_ a: UInt64, _ b: UInt64) -> UInt64 {
            let result = a.addingReportingOverflow(b)
            return result.overflow ? UInt64.max : result.partialValue
        }
        return TrafficBytes(received: saturated(left.received, right.received), sent: saturated(left.sent, right.sent))
    }
}

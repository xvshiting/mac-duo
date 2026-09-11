import Foundation
import IOKit.hid
import FocusCore

/// All HID access is serialized off the UI thread. No keyboard/input event access.
final class LidSensor {
    private let queue = DispatchQueue(label: "app.macduo.hinge", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var attempts = 0
    private var failures = 0
    private var generation = 0

    func start(_ receive: @escaping (Double?) -> Void) {
        generation += 1
        let token = generation
        queue.async { [self] in
            cleanup()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: 1.0 / 30, leeway: .milliseconds(3))
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let value = self.read()
                DispatchQueue.main.async { [weak self] in
                    guard self?.generation == token else { return }
                    receive(value)
                }
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        generation += 1
        queue.async { [self] in cleanup() }
    }

    private func cleanup() {
        timer?.cancel(); timer = nil
        if let device { IOHIDDeviceClose(device, 0) }
        if let manager { IOHIDManagerClose(manager, 0) }
        device = nil; manager = nil; attempts = 0; failures = 0
    }

    private func connect() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let match: [String: Any] = [kIOHIDVendorIDKey: 0x05ac, kIOHIDDeviceUsagePageKey: 0x20, kIOHIDDeviceUsageKey: 0x8a]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        guard IOHIDManagerOpen(manager, 0) == kIOReturnSuccess else { return }
        self.manager = manager
        for candidate in IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [] {
            guard IOHIDDeviceOpen(candidate, 0) == kIOReturnSuccess else { continue }
            if readDevice(candidate) != nil { device = candidate; return }
            IOHIDDeviceClose(candidate, 0)
        }
        IOHIDManagerClose(manager, 0)
        self.manager = nil
    }

    private func readDevice(_ device: IOHIDDevice) -> Double? {
        var report = [UInt8](repeating: 0, count: 8)
        var length = report.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length) == kIOReturnSuccess,
              length >= 3 else { return nil }
        return FocusModel.decode(report: Array(report.prefix(length)))
    }

    private func read() -> Double? {
        if device == nil {
            if attempts % 60 == 0 { connect() }
            attempts += 1
        }
        guard let device else { return nil }
        let value = readDevice(device)
        failures = value == nil ? failures + 1 : 0
        if failures >= 10 {
            IOHIDDeviceClose(device, 0)
            self.device = nil
            if let manager { IOHIDManagerClose(manager, 0) }
            manager = nil; attempts = 0; failures = 0
        }
        return value
    }
}

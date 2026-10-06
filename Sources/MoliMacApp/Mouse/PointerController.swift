import Foundation
import IOKit.hidsystem
import MoliMacCore

/// Sets pointer acceleration and speed on connected mice through the HID event
/// system, the same properties System Settings changes. The values in place before
/// are kept per device and put back when the setting is cleared, the module is
/// turned off or the app quits.
@MainActor
final class PointerController {
    private static let linearKey = "HIDUseLinearScalingMouseAcceleration" as CFString
    private static let resolutionKey = "HIDPointerResolution" as CFString
    /// macOS's resolution for mice that do not report one: 400 dpi in 16.16 fixed point.
    private static let defaultResolution = 400 << 16

    private let client: IOHIDEventSystemClient?
    private var settings = PointerSettings()
    private var active = false
    /// Original property values per device, keyed by registry ID then property.
    private var originals: [UInt64: [String: CFTypeRef]] = [:]
    private var timer: Timer?

    init() {
        client = Self.makeClient()
        if client == nil {
            Log.mouse.error("no HID event system client; pointer settings are off")
        }
    }

    /// The full client can change device properties; the public simple one may not.
    private static func makeClient() -> IOHIDEventSystemClient? {
        typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<IOHIDEventSystemClient>?
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        if let symbol = dlsym(handle, "IOHIDEventSystemClientCreate"),
           let client = unsafeBitCast(symbol, to: Create.self)(kCFAllocatorDefault)
        {
            return client.takeRetainedValue()
        }
        return IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
    }

    func update(_ settings: PointerSettings, active: Bool) {
        self.settings = settings
        self.active = active
        let changesSomething = active && (settings.acceleration != nil || settings.speed != nil)
        apply()
        timer?.invalidate()
        timer = nil
        if changesSomething {
            // Mice plugged in or woken later get the setting on the next pass.
            timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.apply()
                }
            }
        }
    }

    func restoreAll() {
        update(PointerSettings(), active: false)
    }

    private func apply() {
        for service in mice() {
            guard let id = Self.registryID(of: service) else { continue }
            let linear: CFTypeRef? = active ? settings.acceleration.map { ($0 ? 0 : 1) as NSNumber } : nil
            set(Self.linearKey, to: linear, on: service, id: id)

            var resolution: CFTypeRef?
            if active, let speed = settings.speed {
                let original = (originals[id]?[Self.resolutionKey as String] as? NSNumber)?.intValue
                    ?? (IOHIDServiceClientCopyProperty(service, Self.resolutionKey) as? NSNumber)?.intValue
                    ?? Self.defaultResolution
                // A higher resolution means more counts per pixel, so a slower pointer.
                resolution = NSNumber(value: Int(Double(original) / speed))
            }
            set(Self.resolutionKey, to: resolution, on: service, id: id)
        }
    }

    /// Sets `value`, or puts back the original when `value` is nil.
    private func set(_ key: CFString, to value: CFTypeRef?, on service: IOHIDServiceClient, id: UInt64) {
        let name = key as String
        let current = IOHIDServiceClientCopyProperty(service, key)
        if let value {
            if originals[id]?[name] == nil, let current {
                originals[id, default: [:]][name] = current
            }
            if !Self.equal(current, value), !IOHIDServiceClientSetProperty(service, key, value) {
                Log.mouse.error("could not set \(name, privacy: .public)")
            }
        } else if let original = originals[id]?.removeValue(forKey: name) {
            if !Self.equal(current, original) {
                _ = IOHIDServiceClientSetProperty(service, key, original)
            }
        }
    }

    private func mice() -> [IOHIDServiceClient] {
        guard let client, let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return []
        }
        return services.filter { service in
            let isMouse = IOHIDServiceClientConformsTo(
                service,
                UInt32(kHIDPage_GenericDesktop),
                UInt32(kHIDUsage_GD_Mouse)
            )
            let isTrackpad = IOHIDServiceClientConformsTo(
                service,
                UInt32(kHIDPage_Digitizer),
                UInt32(kHIDUsage_Dig_TouchPad)
            )
            return isMouse != 0 && isTrackpad == 0
        }
    }

    private static func registryID(of service: IOHIDServiceClient) -> UInt64? {
        (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value
    }

    private static func equal(_ lhs: CFTypeRef?, _ rhs: CFTypeRef?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return CFEqual(lhs, rhs)
    }
}

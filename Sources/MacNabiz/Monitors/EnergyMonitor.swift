import Foundation
import IOKit
import IOKit.ps

struct EnergyStats {
    var hasBattery: Bool
    var percent: Double
    var isCharging: Bool
    var onACPower: Bool
    var timeRemaining: Int   // dakika, -1 = hesaplanıyor
    var health: String       // "Good" vb.
    var cycleCount: Int

    static let none = EnergyStats(hasBattery: false, percent: 0, isCharging: false,
                                  onACPower: true, timeRemaining: -1, health: "", cycleCount: 0)
}

/// Pil/enerji durumunu IOPowerSources ve AppleSmartBattery'den okur (sudo gerektirmez).
final class EnergyMonitor: Sendable {
    func stats() -> EnergyStats {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as Array
        guard let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return .none   // masaüstü / pil yok
        }

        let current = (desc[kIOPSCurrentCapacityKey] as? Int) ?? 0
        let maxCap  = (desc[kIOPSMaxCapacityKey] as? Int) ?? 100
        let percent = maxCap > 0 ? Double(current) / Double(maxCap) * 100 : 0
        let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        let state = (desc[kIOPSPowerSourceStateKey] as? String) ?? ""
        let onAC = (state == kIOPSACPowerValue)
        let time = charging
            ? ((desc[kIOPSTimeToFullChargeKey] as? Int) ?? -1)
            : ((desc[kIOPSTimeToEmptyKey] as? Int) ?? -1)
        let health = (desc["BatteryHealth"] as? String) ?? ""

        return EnergyStats(
            hasBattery: true,
            percent: percent,
            isCharging: charging,
            onACPower: onAC,
            timeRemaining: time,
            health: health,
            cycleCount: Self.cycleCount()
        )
    }

    private static func cycleCount() -> Int {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        let prop = IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)
        return (prop?.takeRetainedValue() as? Int) ?? 0
    }
}

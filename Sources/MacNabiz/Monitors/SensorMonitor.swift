import Foundation
import CSensors

struct SensorStats {
    var cpuTemp: Double      // °C, 0 = okunamadı
    var maxTemp: Double
    var batteryTemp: Double
    var fans: [Double]       // RPM
    var available: Bool

    static let zero = SensorStats(cpuTemp: 0, maxTemp: 0, batteryTemp: 0, fans: [], available: false)
}

/// Sıcaklık (IOHID) ve fan (SMC) sensörlerini C ara katmanı üzerinden okur.
/// Durumsuzdur; C katmanının paylaşılan istemcileri nedeniyle yalnızca SystemMonitor'ın seri kuyruğundan çağrılır.
final class SensorMonitor: @unchecked Sendable {
    func stats() -> SensorStats {
        var thermal = CThermal()
        let ok = cs_read_thermal(&thermal) != 0

        var fanBuffer = [Double](repeating: 0, count: 8)
        let fanCount = Int(cs_read_fans(&fanBuffer, 8))
        let fans = Array(fanBuffer.prefix(fanCount)).filter { $0 > 0 }

        return SensorStats(
            cpuTemp: thermal.cpuTemp,
            maxTemp: thermal.maxTemp,
            batteryTemp: thermal.batteryTemp,
            fans: fans,
            available: ok
        )
    }
}

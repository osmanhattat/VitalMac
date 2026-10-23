import Foundation
import SwiftUI

/// Tüm izleyicileri tek bir gözlemlenebilir kaynakta toplar.
/// Hafif metrikleri (CPU/RAM/disk) ana iş parçacığında, ağır işlem listesini
/// arka plan kuyruğunda örnekler ve grafik geçmişini tutar.
@MainActor
final class SystemMonitor: ObservableObject {
    @Published var cpu: Double = 0
    @Published var cpuUser: Double = 0
    @Published var cpuSystem: Double = 0
    @Published var memory: MemoryStats = .zero
    @Published var disk: DiskStats = .zero
    @Published var processes: [ProcInfo] = []
    @Published var cpuHistory: [Double] = []
    @Published var memHistory: [Double] = []

    @Published var gpu: GPUStats = .zero
    @Published var network: NetworkStats = .zero
    @Published var energy: EnergyStats = .none
    @Published var sensors: SensorStats = .zero
    @Published var gpuHistory: [Double] = []
    @Published var netDownHistory: [Double] = []
    @Published var netUpHistory: [Double] = []
    @Published var tempHistory: [Double] = []

    let coreCount = ProcessInfo.processInfo.processorCount

    private let cpuMon = CPUMonitor()
    private let memMon = MemoryMonitor()
    private let diskMon = DiskMonitor()
    private let procMon = ProcessMonitor()
    private let gpuMon = GPUMonitor()
    private let netMon = NetworkMonitor()
    private let energyMon = EnergyMonitor()
    private let sensorMon = SensorMonitor()

    /// 0–100 arası genel sistem sağlık skoru (yüksek = iyi).
    var healthScore: Int {
        var score = 100.0
        score -= cpu * 0.25                         // CPU yükü
        score -= memory.pressure * 0.30             // bellek baskısı
        score -= max(0, disk.usedPercent - 75) * 1.2 // disk dolarsa ceza
        if sensors.available, sensors.cpuTemp > 80 {
            score -= (sensors.cpuTemp - 80) * 1.5    // yüksek sıcaklık
        }
        return max(0, min(100, Int(score.rounded())))
    }

    private var timer: Timer?
    private var tickCount = 0
    private var sensorsInFlight = false
    private var processesInFlight = false
    private let workQueue = DispatchQueue(label: "com.hattat.macnabiz.monitor", qos: .userInitiated)
    private let historyLimit = 45
    private let interval: TimeInterval = 2.0

    func start() {
        guard timer == nil else { return }
        tick()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        tickCount += 1

        // Hafif metrikler — her tikte (2 sn): CPU/RAM/disk/ağ.
        let c = cpuMon.usage()
        let m = memMon.stats()
        let d = diskMon.stats()
        let n = netMon.stats()

        cpu = c.total
        cpuUser = c.user
        cpuSystem = c.system
        memory = m
        disk = d
        network = n

        appendHistory(cpu: c.total, mem: m.pressure)
        appendValue(&netDownHistory, n.downBytesPerSec)
        appendValue(&netUpHistory, n.upBytesPerSec)

        // Yavaş değişen ağır okumalar — 2 tikte bir (4 sn), arka planda: GPU/enerji/sensör.
        // IORegistry/SMC/IOHID çağrıları ana iş parçacığını bloklamasın. Seri kuyruk sayesinde
        // C katmanındaki (CSensors) paylaşılan istemcilere tek iş parçacığından erişilir.
        if tickCount % 2 == 0 && !sensorsInFlight {
            sensorsInFlight = true
            let (gm, em, sm) = (gpuMon, energyMon, sensorMon)
            workQueue.async {
                let g = gm.stats()
                let e = em.stats()
                let s = sm.stats()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.gpu = g
                    self.energy = e
                    self.sensors = s
                    self.appendValue(&self.gpuHistory, g.utilization)
                    self.appendValue(&self.tempHistory, s.cpuTemp)
                    self.sensorsInFlight = false
                }
            }
        }

        // İşlem listesi (en pahalı) — 2 tikte bir, arka planda. Önceki örnek bitmeden yenisi başlamaz.
        if tickCount % 2 == 1 && !processesInFlight {
            processesInFlight = true
            let mon = procMon
            workQueue.async {
                let procs = mon.snapshot().sorted { $0.cpu > $1.cpu }
                Task { @MainActor [weak self] in
                    self?.processes = procs
                    self?.processesInFlight = false
                }
            }
        }
    }

    private func appendHistory(cpu: Double, mem: Double) {
        appendValue(&cpuHistory, cpu)
        appendValue(&memHistory, mem)
    }

    private func appendValue(_ buffer: inout [Double], _ value: Double) {
        buffer.append(value)
        if buffer.count > historyLimit { buffer.removeFirst() }
    }
}

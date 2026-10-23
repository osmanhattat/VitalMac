# MacNabız ⚡️

macOS için native (SwiftUI) sistem izleme ve hızlandırma uygulaması.
Disk/RAM/CPU kullanımını gösterir, gereksiz arka plan işlerini kapatır, önbellek temizler.

> Apple Silicon · macOS 14+ · Swift 6 / SwiftUI · Electron'a göre çok daha hafif

## Özellikler

| Bölüm | Ne yapar |
|-------|----------|
| **Panel** | **Sağlık skoru** + Canlı CPU / GPU / Bellek / Disk halkaları, geçmiş grafikleri, **ağ hızı**, **pil/enerji**, **CPU sıcaklığı & fan RPM**, en çok kaynak tüketen işlemler |
| **Donanım** | Çip (örn. Apple M5 Pro), CPU çekirdek yapısı (P+E), **GPU adı/çekirdek sayısı/bellek (GB)**, toplam RAM, model, macOS — canlı kullanım çubukları + Bluetooth cihaz pilleri |
| **İşlemler** | Tüm işlemler tablosu — CPU/Bellek/PID'e göre sıralanır, arama, kapat / zorla kapat |
| **Disk Analizi** | Paralel `fts` tarayıcı (ev klasörü ~2M dosya ≈ 25 sn), canlı ilerleme, sonuç önbelleği (sayfa değişince yeniden taramaz) · treemap + drill-down · **en büyük dosyalar** ve **yinelenenler** aynı taramadan · gizli klasörler dahil · sağ tık: Finder / yolu kopyala / çöpe taşı |
| **Ağ** | Uygulama-bazlı canlı ağ kullanımı (↓↑), `nettop` ile, sıralanabilir tablo |
| **Hızlandır** | Tek tuşla: inaktif belleği boşalt (`purge`) + seçili arka plan uygulamalarını kapat |
| **Temizlik** | Önbellek / log / Xcode DerivedData / çöp kutusu — **silinecek her öğenin dökümü** (ad+boyut) + güvenlik notu, onaylı silme |
| **Alan Kazan** | Geri kazanılabilir alanlar: proje derleme çıktıları (node_modules, bin/obj, build, Pods, venv…), NuGet/npm/Gradle/pnpm önbellekleri, eski iOS simülatör runtime'ları, Xcode DerivedData, Android SDK, aerial duvar kağıtları, eski indirmeler — güvenlik etiketiyle, çöpe taşıyarak |
| **Uygulamalar** | Uygulama kaldırıcı — uygulama + artık dosyaları bulup çöpe taşır |
| **Başlangıç** | Girişte aç ayarı + kullanıcı LaunchAgents yönetimi |
| **Ayarlar** | Eşik bildirimleri (CPU/RAM/disk/sıcaklık) + haftalık otomatik temizlik |
| **Menü çubuğu** | Canlı mini CPU grafiği + CPU/GPU/RAM/Disk/ağ/pil/sıcaklık özeti + hızlı eylemler |

## Derleme & Çalıştırma

```bash
# Geliştirme derlemesi
swift build && swift run

# .app paketi üret (ad-hoc imzalı)
./build-app.sh
open "MacNabız.app"
```

## İzinler

- **Tüm Diske Erişim** — sistem genelini taramak için: *Sistem Ayarları → Gizlilik ve Güvenlik → Tüm Diske Erişim* → MacNabız ekle.
- **Yönetici şifresi** — "Hızlandır"da bellek temizleme (`purge`) yönetici izni ister; macOS şifre penceresi açılır.

## Teknik Mimari

```
Sources/MacNabiz/
Sources/CSensors/    Sıcaklık (IOHID) + fan (SMC) için C ara katmanı
Sources/MacNabiz/
├── App/         MacNabizApp (giriş), RootView (kenar çubuğu + menü çubuğu)
├── Monitors/    CPU/Memory/Disk/Process/GPU/Network/Energy/Sensor/Hardware/Bluetooth → SystemMonitor
├── Services/    Booster, CacheCleaner, DiskAnalyzer, DiskExtras (büyük/yinelenen),
│                DiskScanner (fts), DiskScanStore, SpaceSaver, AppUninstaller,
│                LoginItemsService, NotificationManager, Privileged
├── Views/       Panel, Donanım, İşlemler, Disk, Ağ, Hızlandır, Temizlik, Uygulamalar, Başlangıç, Ayarlar
└── Utils/       Biçimlendirme & renk eşikleri
```

- **CPU:** `host_statistics(HOST_CPU_LOAD_INFO)` tick farkı
- **RAM:** `host_statistics64(HOST_VM_INFO64)` — aktif+wired+sıkıştırılmış
- **GPU:** IORegistry `IOAccelerator → PerformanceStatistics → Device Utilization %` (sudo gerekmez)
- **Ağ:** `getifaddrs` (toplam) + `nettop` (uygulama-bazlı), saniyelik hıza türevlenir
- **Enerji:** `IOPowerSources` + `AppleSmartBattery` (yüzde, şarj, süre, sağlık, çevrim)
- **Sıcaklık:** `IOHIDEventSystemClient` termal sensörleri (SoC die ortalaması)
- **Fan:** `AppleSMC` (`IOConnectCallStructMethod`, `FNum`/`F0Ac`…)
- **Donanım:** `sysctl` + Metal (`recommendedMaxWorkingSetSize`) + IORegistry (`gpu-core-count`)
- **İşlemler:** `proc_listpids` + `proc_pidinfo(PROC_PIDTASKINFO)` ile CPU zaman farkı
- **İkon:** `generate-icon.swift` (CoreGraphics ile çizilen nabız temalı .icns)

## Güvenlik notu

Silme işlemleri (Temizlik, Kaldırıcı) **her zaman** onay penceresi gösterir ve
mümkün olduğunda öğeleri **çöp kutusuna taşır** (geri alınabilir).

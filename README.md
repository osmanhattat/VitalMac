<div align="center">

<p><b>English</b> · <a href="README.tr.md">Türkçe</a></p>

<img src="docs/icon.png" width="112" alt="MacNabız icon">

# MacNabız

**A local, lightweight system monitor that keeps your Mac's pulse.**<br>
Live CPU, GPU, memory, disk, network, battery and temperature, plus a disk scanner that finds what's eating your space in seconds and cleans it safely.

<p>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-0F172A?style=flat-square&logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-native-0F172A?style=flat-square">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="No network access" src="https://img.shields.io/badge/network-none-16A34A?style=flat-square">
  <img alt="MIT license" src="https://img.shields.io/badge/license-MIT-2563EB?style=flat-square">
</p>

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshot-dark.png">
  <img alt="MacNabız dashboard: system pulse, live ECG trace and CPU, GPU, memory and disk channels" src="docs/screenshot-light.png">
</picture>

> *Nabız* is Turkish for "pulse". The interface is currently in Turkish; English localization is planned.

## Why MacNabız

- **Status at a glance.** The ECG trace at the top of the dashboard speeds up with CPU load; below it, four channels (CPU, GPU, memory, disk) show their last minute of history.
- **Disk scans in seconds.** A 290 GB home folder with 2 million files is scanned in **24 seconds** (`du` on the same folder: 104 s). Folder sizes, largest files and duplicate candidates all come from a single pass.
- **Tells you what's safe to delete.** The *Alan Kazan* (Reclaim Space) page lists regenerable space — `node_modules`, `bin/obj`, package caches, old iOS Simulator runtimes — **by project name**, and labels every item *Safe* or *Check first*.
- **Nothing leaves your Mac.** The app makes no network connections and sends no telemetry; every reading comes from local system APIs.

## Features

| | Section | What it does |
|---|---|---|
| **Monitor** | Dashboard | Health score, CPU-driven live pulse trace, CPU / GPU / memory / disk channels, network speed, battery, temperature and fans, top processes |
| | Hardware | Chip, P+E core layout, GPU cores and memory, model, macOS version, Bluetooth device batteries |
| | Processes | Searchable, sortable process table; quit / force quit |
| | Network | Live per-app download / upload rates |
| **Storage** | Disk Analysis | Parallel scanner with live progress, treemap with drill-down, largest files, duplicate finder; right-click to reveal in Finder / copy path / move to Trash |
| | Reclaim Space | Project build outputs, developer caches (NuGet, npm, pnpm, Gradle, CocoaPods…), Simulator runtimes, Xcode DerivedData, Android SDK, aerial wallpapers, old downloads |
| | Cleanup | Caches, logs, DerivedData and Trash, with an itemized list of everything to be removed |
| **Maintenance** | Boost | Free inactive memory and quit selected background apps |
| | Apps | Uninstaller that moves an app and its leftovers to the Trash |
| | Startup | Open-at-login setting and user LaunchAgents |
| **Everywhere** | Menu bar | Live mini graph, summary values and quick actions |
| | Settings | Threshold alerts (CPU, RAM, disk, temperature) and weekly automatic maintenance |

## Safety principles

MacNabız can delete files, so it follows these rules:

1. **Show first, then ask.** Everything to be removed is listed with its name, path and size; nothing happens without confirmation.
2. **Trash by default.** Disk Analysis and Reclaim Space never delete permanently — items go to the Trash and can be restored.
3. **Protected locations.** Anything outside your home folder, top-level folders such as `~/Desktop`, and sensitive `~/Library` areas (Keychains, Mail, Messages, iCloud…) can't be trashed, and symlinks can't be used to escape.
4. **Hands off active projects.** Build outputs of projects modified in the last 60 days are not selected by default.
5. **No shell.** External tools (`simctl`, `osascript`) are run with argument arrays; anything needing admin rights goes through the standard macOS password prompt.

## Installation

Requirements: macOS 14 or later, Xcode command line tools (Swift 5.9+).

```bash
git clone https://github.com/osmanhattat/MacNabiz.git
cd MacNabiz
./build-app.sh                       # release build + ad-hoc signed MacNabız.app
cp -R "MacNabız.app" /Applications/
open "/Applications/MacNabız.app"
```

For development: `swift build && swift run`

> The app is ad-hoc signed. If macOS warns on first launch, right-click it in Finder → **Open** and confirm once.

### Permissions

| Permission | Why | Where |
|---|---|---|
| Full Disk Access | Lets Disk Analysis measure protected folders too | System Settings → Privacy & Security → Full Disk Access |
| Administrator password | Only when freeing memory (`purge`) | macOS asks at that moment |
| Automation (Finder) | Only for the *Empty Trash* button | macOS asks on first use |

## How it measures

| Reading | Source |
|---|---|
| CPU | `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas |
| Memory | `host_statistics64(HOST_VM_INFO64)` — active + wired + compressed |
| GPU | IORegistry `IOAccelerator → PerformanceStatistics` (no sudo) |
| Network | `getifaddrs` (totals), `nettop` (per app) |
| Battery | `IOPowerSources` + `AppleSmartBattery` |
| Temperature / fans | `IOHIDEventSystemClient` thermal sensors, `AppleSMC` |
| Disk scan | `fts(3)` + `lstat`, parallel tasks for the first three levels, hard links counted once |

## Architecture

```
Sources/
├── CSensors/           C layer for temperature (IOHID) and fans (SMC)
└── MacNabiz/
    ├── App/            Entry point, sidebar, menu bar
    ├── Monitors/       CPU, memory, disk, GPU, network, energy, sensors → SystemMonitor
    ├── Services/       DiskScanner (fts), DiskScanStore, SpaceSaver, CacheCleaner,
    │                   AppUninstaller, Booster, LoginItemsService, NotificationManager
    ├── Views/          Theme (design tokens), Components, pages
    └── Utils/          Formatting
```

## License

[MIT](LICENSE) © 2026 Osman Safa Hattat

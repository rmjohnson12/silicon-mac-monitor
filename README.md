<div align="center">

# Silicon

**A closer look at your Mac.**

A native macOS monitor for CPU, memory, processes, temperatures, and fans.
Built with SwiftUI, graphite surfaces, and soft mint accents.

[![Build](https://github.com/rmjohnson12/silicon-mac-monitor/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/rmjohnson12/silicon-mac-monitor/actions/workflows/build.yml)
![macOS](https://img.shields.io/badge/macOS-14%2B-242b27)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138)

![Silicon interface preview](docs/assets/silicon-preview.png)

*Illustrative interface preview with sample values. The running app collects live readings.*

</div>

## What it does

| View | What you can see |
| --- | --- |
| **Overview** | CPU, memory, CPU/GPU temperatures, thermal state, fans, and leading processes |
| **CPU** | Overall user/system utilization, individual cores, and live history |
| **Memory** | App/wired/compressed memory, available memory, cache, swap, and kernel memory pressure |
| **Thermals** | CPU temperature history, available hardware sensors, fan RPM, and macOS thermal pressure |
| **Processes** | Search by name or PID, sort columns, filter CPU users, inspect a process, and reveal its executable in Finder |
| **Menu bar** | A compact stats panel and current CPU usage, available after closing the main window |

Choose a 1-, 2-, or 5-second refresh interval, switch temperature readouts between Celsius and Fahrenheit, pause monitoring, or export a local JSON snapshot. Charts retain up to 15 minutes of collected samples in memory.

## Build and run

Requires **macOS 14 or later**, **Swift 5.9 or later**, and Apple's Command Line Tools or Xcode. There are no third-party Swift package dependencies.

```sh
git clone https://github.com/rmjohnson12/silicon-mac-monitor.git
cd silicon-mac-monitor
./scripts/build-app.sh
open dist/Silicon.app
```

The build script creates a native app bundle with its icon and an ad-hoc signature for local use. This repository distributes source; the app is **not notarized for public binary distribution**. The binary is built for the current Mac's architecture.

To install it, quit Silicon and copy `dist/Silicon.app` into your `~/Applications` folder. You can also use `Launch Silicon.command`, which opens an installed copy or builds and opens the project copy if needed.

## Compatibility

Live hardware validation was performed on a **14-core Apple M3 Max MacBook Pro with 36 GB of unified memory, running macOS 26.7.2**.

The CPU and memory collectors use macOS APIs and discover the machine's core count and physical memory at runtime. Temperature mappings are primarily implemented for the M3 family, with limited legacy CPU sensor probes. Sensor labels use community mappings and are not guaranteed across models or macOS releases. Other Macs have not been validated.

Unavailable sensors display **—** or an explicit unavailable message. A successful **0 RPM** reading is retained: some Apple silicon Macs stop their fans when cooling demand is low. Silicon reads fan speeds; macOS manages cooling.

## Understanding the readings

**CPU:** Overall utilization uses Mach per-core tick deltas, normalized to 0–100% across the machine. Process CPU uses `/bin/ps`'s decayed average, where **100% represents one core**; multithreaded processes can exceed 100%. Different scales and averaging windows mean the process figures will not add exactly to overall usage.

**Memory:** Used memory is an approximation of app + wired + physical compressed pages. App memory is anonymous pages minus purgeable pages; available memory includes reclaimable cache. Pressure is read from the kernel. Process memory is resident size (RSS), so shared pages may be counted in multiple processes. Values can differ from Activity Monitor.

**Thermals:** Thermal pressure uses Apple's documented `ProcessInfo.thermalState`. Hardware temperatures and fans use a **read-only AppleSMC connection**, without administrator access or a privileged helper. CPU/GPU readings are averages of responding sensors, rather than a hottest-core or package-temperature claim. The temperature history chart stays explicitly labeled in Celsius when readouts are set to Fahrenheit.

## Privacy

- Collection and charts run locally. The app has no account, analytics, or network requests.
- History stays in memory and is discarded when the app quits.
- JSON snapshots are written only when you choose to export them. They include process names, PIDs, resource usage, and sensor readings, and omit executable paths, command-line arguments, and the Mac's serial number.
- Build output, local screenshots, exported verification data, and sharing drafts are excluded from version control. The public preview uses sample values.

## Verify

```sh
swift build -c release --build-system native
.build/release/Silicon --self-test
.build/release/Silicon --diagnostics
```

`--self-test` runs **18 regression checks** covering process parsing, multicore CPU values, memory bounds, missing readings, temperature conversion, and JSON exports. The runner does not require XCTest.

`--diagnostics` samples real hardware and exits nonzero if CPU, memory, or process validation fails. It reports the sensors that respond, without requiring sudo or opening a window. Hardware diagnostics are a local check; CI builds the app and runs the deterministic regression checks.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘1`–`⌘5` | Change views |
| `⇧⌘P` | Pause or resume |
| `⌘F` | Search in Processes |
| `⇧⌘E` | Export a snapshot |
| `⌘,` | Open preferences |

## Implementation and attribution

The app uses SwiftUI and Charts for the interface, Mach APIs for CPU/memory counters, `ps` for process sampling, and a small C bridge for read-only AppleSMC access. It was developed with assistance from OpenAI Codex.

- [Apple: thermal state](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)
- [Apple: Mach memory statistics](https://developer.apple.com/documentation/kernel/1502863-host_statistics64)
- [SMCKit: SMC protocol reference](https://github.com/beltex/SMCKit)
- [Stats: community sensor identifiers](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift)

Third-party attribution and the SMCKit MIT notice are included in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

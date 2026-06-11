# NetICU

**Live internet-quality and server-performance monitor for macOS.**

NetICU sits in your menu bar and continuously measures the health of your connection to the targets you care about — websites, servers, APIs — and tells you at a glance whether problems are on your side or theirs.

## Features

- **Ping, jitter, packet loss** — measured over a rolling 2-minute window with 95th-percentile (p95) stats.
- **Timing breakdown** — DNS / TCP / TLS / TTFB phases for each probe, so you can see *where* the latency lives.
- **Menu-bar gauge** — two live ping numbers with a fillable quality gauge, always visible.
- **Dashboard** — overview of all monitors with charts and quality scores.
- **Server vs. network diagnosis** — helps distinguish "my internet is bad" from "their server is slow."
- **Per-monitor proxy** — route individual monitors through a proxy (macOS 14+).
- **Alert notifications** — get notified when a target degrades or goes down.
- **Public IP display, recent logs, history clearing, calibration of quality thresholds.**

## Installation

Download `NetICU-1.4.0.zip` from the [Releases](https://github.com/aahonarmand/NetICU/releases) page, unzip it, and move `NetICU.app` to your Applications folder.

> **First launch — "NetICU can't be opened":** the app is not yet notarized by Apple, so macOS Gatekeeper blocks it on first launch. To allow it:
>
> 1. **Right-click** (or Control-click) `NetICU.app` and choose **Open**, then click **Open** in the dialog, **or**
> 2. Go to **System Settings → Privacy & Security**, scroll down to the message about NetICU, and click **Open Anyway**.
>
> This is only needed once. Alternatively, build from source (below) — apps you build yourself launch without this warning.

## Requirements

- macOS 13 or later (per-monitor proxy requires macOS 14+)
- Xcode 16+ to build from source

## Building

1. Clone the repository:
   ```sh
   git clone https://github.com/aahonarmand/NetICU.git
   ```
2. Open `NetICU.xcodeproj` in Xcode.
3. Select the **NetICU** scheme and press **⌘R**.

The project uses filesystem-synchronized groups (Xcode 16+), so any `.swift` file placed in the `NetICU/` folder is picked up automatically.

## Architecture

| File | Role |
|---|---|
| `NetICUApp.swift` | App entry point, menu-bar gauge, settings window |
| `Models.swift` | Data models, rolling-window statistics, calibration |
| `PingEngine.swift` | Measurement engine (URLSession, proxy support) |
| `MonitorViewModel.swift` | Monitoring loop, history, IP, notifications, sorting |
| `ContentView.swift` | Main window, monitor details, logs |
| `DashboardView.swift` | Dashboard view |
| `Components.swift` | Cards, charts, gauges |
| `AboutView.swift` | About screen and metrics glossary |
| `Localization.swift` | UI strings |

## Roadmap

- Bufferbloat / latency-under-load (RPM)
- Bandwidth measurement (download/upload)
- Wi-Fi quality (RSSI) via CoreWLAN
- Configurable statistics window length
- Windows/Linux version

## Changelog

| Version | Highlights |
|---|---|
| 1.4.0 | Fillable menu-bar gauge, quality calibration thresholds, outage chart-drop fix |
| 1.3.0 | English-only UI, per-monitor proxy, server/network diagnosis, alert notifications, recent logs, clear history |
| 1.2.0 | About section, in-app metric help, version display |
| 1.1.0 | Timing breakdown (DNS/TCP/TLS/TTFB) and p95 |
| 1.0.0 | First release: ping, jitter, loss, dashboard, IP, sorting |

## License

[MIT](LICENSE) © Aliasghar Honarmand

*Developed by Aliasghar Honarmand in collaboration with Claude.*

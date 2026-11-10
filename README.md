<p align="center">
  <img src="docs/social-preview.svg" width="100%" alt="MacStatus: your Mac's vitals, one glance from the menu bar. A native Swift monitor for Apple Silicon: power, temperatures, CPU, GPU, memory, disks and network.">
</p>

# MacStatus

A system monitor that lives in the macOS menu bar. Native Swift and SwiftUI, built with SwiftPM, no root helper and no Xcode project.

The menu bar item shows the **live system power draw** and **CPU temperature** stacked on the left, with the **upload** (red) and **download** (blue) speed on the right. Click it for the full popup.

<p>
  <img src="docs/menubar.png" width="536" alt="The menu bar item on a dark and a light menu bar: 22 W and 63° stacked, a red dot with 1.0 MB/s upload and a blue dot with 40 KB/s download">
</p>

## The popup

<p>
  <img src="docs/popup.png" width="370" alt="The popup: the chip and charger in the header with a thermal state pill, CPU and GPU cards with usage, history and temperature, a memory card with a bar split into app, wired, compressed and cached, the top processes by CPU and by memory, the energy card, the network card with live speeds, Wi-Fi details and public and local addresses, and one card per connected disk">
  <img src="docs/energy-states.png" width="370" alt="The energy card in its three states: charging in green, discharging in red, and plugged in without charging in blue">
</p>

| Card | What it shows |
| --- | --- |
| **Header** | The MacStatus logo, chip name and core count, the connected charger, the system's thermal state, **Refresh** and **Quit** |
| **CPU** and **GPU** | Utilisation with a short history, user / system split, performance and efficiency cores, GPU memory and core count, temperatures |
| **Memory** | Used and total, memory pressure, and a bar split into app, wired, compressed and cached |
| **Top processes** | The five busiest by CPU and by memory, side by side. Rows are grouped by app bundle |
| **Energy and power** | Battery level and power, charger input and rating, total system draw, battery health, cycle count, temperature, time remaining or time to full |
| **Network** | Connection type (Wi-Fi, Ethernet, VPN), download and upload speed with a shared history chart, traffic totals. On Wi-Fi: network name, signal, channel and band, link rate; on Ethernet: adapter and link speed. **Public** IP, ISP, ASN and location, and **local** IP and subnet, router, DNS and MAC address. Click an address to copy it |
| **Disks** | One card per connected disk: name, model, capacity used, read and write speed, temperature |

The energy card's colour tells you what the battery is doing at a glance:

| State | Colour |
| --- | --- |
| Charging | green |
| Discharging | red |
| Plugged in, not charging | blue |

The right-click menu has **Refresh Now**, **Launch at Login** and **Quit MacStatus**.

**Wi-Fi name.** macOS only reveals the Wi-Fi network name to apps that may use Location Services. Click **Show name** in the network card to allow it; MacStatus never reads your location. Until then the rest of the Wi-Fi details still show.

## Requirements

- A Mac with Apple Silicon, running macOS 14 or newer.
- A Swift 5.9+ toolchain (Xcode or the Command Line Tools).

It was built and tested on an M4 MacBook on macOS 26. The sensors are read by key, so a different chip may be missing some of them. A value that can't be read is left out instead of shown as zero.

## Install

```sh
Scripts/install.sh                     # build, copy to /Applications and start it
Scripts/install.sh ~/Applications      # or another folder named Applications
```

Once it runs from an Applications folder, MacStatus **starts at login** by itself. macOS confirms with a "Login Item Added" notification, and the item shows up in System Settings › General › Login Items. Untick **Launch at Login** in the right-click menu to turn that off; it stays off across updates. Running `install.sh` again quits the running copy and replaces it.

## Build and run

```sh
Scripts/build-app.sh          # release build -> build/MacStatus.app (ad-hoc signed)
open build/MacStatus.app
```

`Scripts/build-app.sh debug` makes a debug build instead. A build run from `build/` doesn't add itself to Login Items, so dev builds never leave a login item pointing into the repo. The app is menu-bar-only (`LSUIElement`), so there is no Dock icon: look for it at the right of the menu bar.

Everything is sampled once a second. The one exception is the process list, which is the expensive part and is only gathered while the popup is open.

## Where the numbers come from

Everything is read without root.

| Value | Source |
| --- | --- |
| System power (the menu bar watts) | SMC key `PSTR`. Charger input comes from `PDTR` |
| CPU temperature | Average of the SMC `Tp*` and `Te*` sensors (performance and efficiency cores), found by prefix. Falls back to the HID `PMU tdie` sensors |
| GPU temperature | Average of the SMC `Tg*` sensors |
| Internal SSD temperature | The HID sensor named `NAND` |
| External NVMe temperature | The drive's `NVMeSMARTLib` plug-in, cached for 10 s |
| Battery health, cycles, temperature | `AppleSmartBattery` |
| Processes | `libproc` |
| Network speed and totals | 64-bit interface counters from `sysctl` `NET_RT_IFLIST2`, summed over the physical `en*` interfaces |
| Connection, addresses, router, DNS | The SystemConfiguration dynamic store (`State:/Network/Global/IPv4`, `.../DNS`, `.../Interface/<if>/IPv4`) |
| Wi-Fi signal, channel, rate, name | `CoreWLAN`. The name needs Location Services permission |
| Public IP, ISP, location | `ipinfo.io`, falling back to Cloudflare's `1.1.1.1/cdn-cgi/trace` (IP and country only). The public IPv6 address comes from `api6.ipify.org`, asked only when the network has IPv6 |

**Why `PSTR` and not the battery's own telemetry.** `PowerTelemetryData` inside `AppleSmartBattery` stays stale for many seconds, so it is only used as a fallback when the SMC read fails.

**The public IP is the only thing fetched from the internet.** It belongs to your router, so it can't be read locally. The lookup runs only while the popup is open, and only when the Mac changes networks, the last answer is 10 minutes old, or you press Refresh. The request sends no cookies and nothing about you beyond what any web request carries: your IP address and a standard system User-Agent.

**Known limits.**

- `libproc` can only read about 300 of the roughly 470 processes without root. Root daemons such as `WindowServer` and `kernel_task` are missing from the top-processes list.
- There are no per-block SoC power numbers (CPU, GPU, ANE watts). That needs IOReport and isn't built yet.

## Not built yet

- Customising the menu bar item (styles and per-item toggles).
- Per-block SoC watts.
- The right-click menu is written but hasn't been clicked through by hand yet.

## Regenerating the screenshots

The images above are rendered by the app itself from live readings, so no screen capture is involved:

```sh
build/MacStatus.app/Contents/MacOS/MacStatus --preview /tmp/macstatus   # popup.png, menubar.png, energy-states.png
build/MacStatus.app/Contents/MacOS/MacStatus --show-popup         # launch with the popup already open
```

`--preview` writes the three PNGs and exits. It also shows the energy card in all three states, using sample values, which is how `energy-states.png` is made. In `popup.png` the addresses, ISP, location and Wi-Fi name are swapped for documentation values (`203.0.113.42`, `192.168.1.24`, "Example Broadband"), so a screenshot never publishes your real network.

The app icon comes from the same SwiftUI view as the logo in the popup header (`Views/AppLogo.swift`). `build-app.sh` renders it with `MacStatus --icon <dir>.iconset` and packs it with `iconutil`, so there's no icon file to keep in sync.

## Layout

```
Sources/MacStatus/
  AppDelegate.swift, main.swift     launch, --preview, --show-popup and --icon
  StatusItemController.swift        the menu bar item, popover and right-click menu
  MenuBarRenderer.swift             draws the stacked readout and the network dots
  PreviewRenderer.swift             renders the popup and menu bar item to PNGs
  Model/                            StatsStore (1 s sampling loop), snapshot types
  Monitors/                         CPU, GPU, memory, network, connection, public IP, power, disks, processes, SMC, HID, NVMe SMART
  Views/                            the popup's SwiftUI cards and the logo (AppLogo.swift, also the app icon)
  Support/                          formatting, launch at login, location permission, low-level system helpers
Scripts/build-app.sh                builds and signs build/MacStatus.app, icon included
Scripts/install.sh                  builds, installs into an Applications folder and starts it
```

## License

MIT. See [LICENSE](LICENSE).

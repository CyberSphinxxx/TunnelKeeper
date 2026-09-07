# TunnelKeeper

A modern Windows gateway that exposes your locally-running Minecraft server to the internet through a free [Pinggy](https://pinggy.io) TCP tunnel, automatically keeping your **Hostinger** or **Cloudflare** DNS SRV records updated. A hot-swap mechanism pre-starts a replacement tunnel before the active one expires, achieving near-zero downtime for players.

Includes a **sleek Windows 11 dark-mode desktop GUI**, system tray minimization, and a **1-line PowerShell installer**.

---

## Quick Install (PowerShell 1-Liner)

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/CyberSphinxxx/TunnelKeeper/main/install.ps1 | iex
```

This automatically:
- Checks & verifies your OpenSSH client.
- Installs TunnelKeeper into `%LOCALAPPDATA%\TunnelKeeper`.
- Creates a **Desktop Shortcut** with custom icon.
- Registers **TunnelKeeper** in your Windows **Start Menu**.
- Launches the GUI dashboard immediately.

*To cleanly uninstall at any time:* `.\install.ps1 -Uninstall`

---

## Modern GUI Dashboard

TunnelKeeper features a native Windows WPF dark-theme dashboard (`TunnelKeeper.exe` or `TunnelKeeper-GUI.ps1`):

- **No File Editing Required**: Configure tokens, domains, and ports directly in the interactive **Settings** tab.
- **Visual Status Badges**: Real-time `🟢 ONLINE` / `🔴 STOPPED` indicators and local Minecraft server health detection.
- **1-Click Copy**: Click **[Copy Server Address]** to immediately copy `play.yourdomain.com` to clipboard for Discord or Minecraft.
- **Live Console Streaming**: Embedded terminal streaming real-time hot-swap activity and Pinggy logs.
- **System Tray Support**: Minimize to the Windows notification tray next to your clock so it keeps your Minecraft server live 24/7 without cluttering your taskbar.

---

## File Structure

```
TunnelKeeper/
├── .github/workflows/
│   ├── release.yml                  # Automated CI/CD: compiles TunnelKeeper-Setup.exe & publishes releases
│   └── ci.yml                       # Continuous Integration: syntax & compilation tests
├── assets/
│   └── TunnelKeeper.ico             # High-resolution application and tray icon
├── scripts/
│   ├── build-exe.ps1                # Native C# compiler script for TunnelKeeper.exe
│   ├── installer.iss                # Inno Setup wizard compiler script
│   ├── TunnelKeeper.bat             # Portable batch launcher
│   └── TunnelKeeper.vbs             # Silent VBScript runner
├── src/
│   ├── main.ps1                     # Unified entrypoint (CLI & GUI dispatcher)
│   ├── TunnelKeeper-GUI.ps1         # Modern native WPF dark-mode dashboard
│   └── minecraft-tunnel-autostart.ps1 # Core daemon (tunneling, DNS dispatcher, hot-swap engine)
├── TunnelKeeper.exe                 # Standalone double-clickable GUI launcher (0 console flash)
├── install.ps1                      # 1-line PowerShell installer & uninstaller
├── .env.example                     # Configuration template with all available settings
├── .env                             # Secret token and config storage (auto-saved by GUI)
├── .gitignore                       # Excludes .env from version control
└── README.md                        # Documentation
```

---

## Requirements

| Requirement | Notes |
|---|---|
| Windows 10 or 11 | Uses Win32 console APIs, Windows mutex, and native WPF |
| PowerShell 5.1 or later | Included in Windows by default |
| OpenSSH client | Built into Windows 10/11; provides the `ssh` command |
| DNS API token | Either **Hostinger** API token or **Cloudflare** API token (with Zone.DNS Edit permissions) |
| Minecraft server | Must be listening on the configured local port (default: `25565`) |

No external runtimes (Python, Node.js, etc.) are required.

---

## Installation Options

### Method A: Windows Setup Wizard (Recommended for End Users)
Download **`TunnelKeeper-Setup.exe`** from the latest [GitHub Releases](https://github.com/CyberSphinxxx/TunnelKeeper/releases). Run the setup wizard to install TunnelKeeper with desktop and Start Menu shortcuts.

### Method B: 1-Line PowerShell Web Installer
Open PowerShell and run:
```powershell
irm https://raw.githubusercontent.com/CyberSphinxxx/TunnelKeeper/main/install.ps1 | iex
```

### Method C: Portable Zip / Manual Clone
1. Download `TunnelKeeper-v3.0.0-Portable.zip` from [GitHub Releases](https://github.com/CyberSphinxxx/TunnelKeeper/releases) or clone this repository.
2. Double-click **`TunnelKeeper.exe`** to start.

---

## Setup & Running

### Using the GUI Dashboard

1. Open **TunnelKeeper** from your Desktop shortcut or double-click **`TunnelKeeper.exe`**.
2. Go to the **Settings** tab.
3. Choose your DNS Provider (**Hostinger** or **Cloudflare**), paste your API token, and enter your domain and server port.
4. Click **Save Settings to .env**.
5. Switch to the **Dashboard** tab and click **[Start Tunnel Gateway]**.

### Option 2: Running via Command Line (CLI Daemon)

Open PowerShell and run:

```powershell
# Run the headless background daemon
.\src\main.ps1 -Headless
```

#### CLI Parameters

| Parameter | Type | Description |
|---|---|---|
| `-Gui` | Switch | Launches the interactive native WPF dashboard (default when no parameters are specified). |
| `-Headless` / `-Daemon` | Switch | Runs the tunneling engine interactively in the terminal console. |
| `-Status` | Switch | Inspects the current state of the gateway without disturbing running services. Displays whether the tunnel is active, local Minecraft server health, public SRV DNS target, active SSH processes, and recent log entries. |
| `-Force` | Switch | Stops the background Task Scheduler task (`Minecraft Tunnel Keeper`), terminates any lingering Pinggy `ssh` processes, and takes over running the tunnel interactively in the current terminal. |
| `-Validate` | Switch | Validates that `.env` is present and necessary provider tokens and domains are set. |
| `-Version` | Switch | Displays the current TunnelKeeper version. |

Examples:
```powershell
# Check live gateway status
.\src\main.ps1 -Status

# Take over and restart the tunnel interactively
.\src\main.ps1 -Force

# Validate configuration
.\src\main.ps1 -Validate
```

#### Viewing Background Logs

If the tunnel is running in the background via Windows Task Scheduler, monitor live output without interrupting it:

```powershell
Get-Content -Path "$HOME\TunnelKeeper_Logs\gateway_$(Get-Date -Format 'yyyy-MM-dd').log" -Wait -Tail 20
```

If you receive an execution policy error when running the script, run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## Configuration

Settings can be configured in `.env` (recommended) or configured directly within the TunnelKeeper GUI Settings tab:

| `.env` Key | Default | Description |
|---|---|---|
| `DnsProvider` | `Hostinger` | DNS provider: `Hostinger` or `Cloudflare` (auto-detected if token is provided) |
| `HostingerToken` | *(none)* | **Required for Hostinger.** Hostinger API token with DNS write permissions |
| `CloudflareApiToken` | *(none)* | **Required for Cloudflare.** Scoped token with Zone.DNS Edit permissions |
| `CloudflareZoneId` | *(auto)* | Optional for Cloudflare; automatically discovered from `RootDomain` if omitted |
| `RootDomain` | *(Required)* | The root DNS zone managed on your DNS provider (e.g. `yourdomain.com`) |
| `SrvRecordName` | `_minecraft._tcp.play` | The SRV record name within the zone (e.g. `_minecraft._tcp.play` for `play.yourdomain.com`) |
| `LocalPort` | `25565` | The local port your Minecraft server listens on (Java default: `25565`) |
| `Priority` | `0` | SRV record priority field (0 - 65535, default: 0) |
| `Weight` | `5` | SRV record weight field (0 - 65535, default: 5) |
| `TTL` | `60` | DNS TTL in seconds (low value ensures fast propagation) |
| `HotSwapMinute` | `55` | Minutes elapsed before a replacement tunnel is pre-started (5 - 59) |
| `LogRetentionDays` | `14` | Days of log files to keep before auto-purging old logs on startup |

---

## How It Works

### Tunnel lifecycle

```
Start-Tunnel
    |-- Launches ssh process with -T (disables PTY for background execution)
    |-- Registers async output/error handlers to capture the assigned URL
    |-- Sends blank stdin lines to bypass password prompts
    |-- Waits up to 60 seconds for a tcp://host:port URL in output
    |-- Returns tunnel object (proc, state, handlers)
```

### DNS update & verification

After a successful tunnel start, the appropriate provider updater is called (`Update-DnsSRV`):

- **Hostinger**: Sends DELETE request for old SRV records, waits 2 seconds, then issues a PUT request with retry backoff.
- **Cloudflare**: In-place PUT/POST request directly to the Cloudflare v4 DNS API targeting the zone.
- **Live Verification**: Performs a `Resolve-DnsName` query against public resolvers to confirm when the new SRV record is live.

### Hot-swap

When the active tunnel has been running for `$HotSwapMinute` minutes (default 55):

1. A second tunnel is started in parallel.
2. DNS is immediately updated to point at the new tunnel and verified.
3. The old tunnel object is kept in memory and monitored. It is cleaned up when Pinggy terminates it naturally, or forcibly after 10 minutes.
4. The monitoring loop switches to the new tunnel seamlessly, incrementing the cycle and swap counters.

### Watchdog

If a tunnel is still alive after 75 minutes (a fallback for cases where Pinggy does not terminate it on schedule), the script force-kills the process and begins a new cycle.

### Duplicate instance guard & Process Safety

- **Named Mutex**: A named Windows mutex (`Global\TunnelKeeper_Gateway`) prevents two instances of the script from running simultaneously. Handles `UnauthorizedAccessException` and `AbandonedMutexException` cleanly without crashing.
- **Task Scheduler Integration**: If a new instance is started while the Windows Task Scheduler task (`Minecraft Tunnel Keeper`) is already active, it displays a clear informational status card confirming the server is live, provides the log file location, status command, and live tail command, and exits cleanly with code `0`.
- **Force Override (`-Force`)**: Launching with `.\minecraft-tunnel-autostart.ps1 -Force` will automatically stop the `Minecraft Tunnel Keeper` background task, forcibly terminate any orphan Pinggy SSH tunnels on the configured port, and take over running interactively in the current terminal.
- **Orphan Process Cleanup**: Registers a PowerShell engine exit hook (`PsEngineEvent::Exiting`) that ensures child `ssh` processes are terminated if the PowerShell terminal is closed abruptly.

---

## Logging

Logs are written to:

```
%USERPROFILE%\TunnelKeeper_Logs\gateway_YYYY-MM-DD.log
```

- **Dynamic Daily Rollover**: Automatically logs to the new date's file at midnight without requiring a script restart.
- **Automatic Retention Cleanup**: Automatically purges log files older than `LogRetentionDays` (default: 14 days) on startup to prevent disk clutter.
- All tunnel events, DNS operations, hot-swap actions, and errors are recorded with timestamps.

---

## Players: How to Connect

Players connect using your configured domain name rather than a raw IP address. Because the script maintains the SRV record, players only ever need to add the server using:

```
play.yourdomain.com
```

No port number is required in the Minecraft client when a valid SRV record is present. The low TTL (60 seconds) means DNS changes propagate to players within about a minute of a hot-swap.

---

## Troubleshooting

**Script exits with "HostingerToken not found" (or CloudflareApiToken)**
Create a `.env` file or use TunnelKeeper GUI -> Settings tab to enter your API token.

**Script exits with "RootDomain is not configured"**
Set your own registered domain name (e.g. `yourdomain.com`) in `.env` or in the GUI Settings tab.

**Tunnel fails to start / No URL detected after 60 seconds**
Confirm the `ssh` command is available (`ssh -V` in a terminal). The OpenSSH client must be installed. Also verify the machine has outbound access on port 443.

**DNS update fails with 4xx errors**
Verify your DNS API token has write permissions for your domain zone and has not expired.

**Console freezes when clicked**
The script disables QuickEdit mode on startup to prevent this. If the terminal was opened before the script ran and QuickEdit was already active, right-click the title bar, choose Properties, and uncheck QuickEdit Mode.

**Another instance is already running**
- If the tunnel was launched by Windows Task Scheduler (`Minecraft Tunnel Keeper`), the domain is already actively maintained in the background. You can inspect live logs with:
  ```powershell
  Get-Content -Path "$HOME\TunnelKeeper_Logs\gateway_$(Get-Date -Format 'yyyy-MM-dd').log" -Wait -Tail 20
  ```
- To stop the background task and force an interactive restart in your current console, run:
  ```powershell
  .\minecraft-tunnel-autostart.ps1 -Force
  ```
- If another manual PowerShell session is open, close that window or run the command above with `-Force` to terminate leftover `ssh` tunnels.

---

## Security Notes

- The `.env` file is excluded from version control by `.gitignore`. Do not commit it.
- The Hostinger API token grants DNS write access to your domain. Treat it as a secret and rotate it if it is ever exposed.
- The script connects to `tcp@a.pinggy.io` on port 443 using SSH with `StrictHostKeyChecking=no`. This bypasses host key verification for Pinggy's server; acceptable for this use case but worth noting.

---

## Background & Problem History

This section documents why this script exists — the full investigation that led to it.

### The Problem

Java Edition players received **"Connection Timed Out"** when trying to join, while Bedrock Edition players connected and played fine through the same hosting setup.

**Server setup at the time:**
- Host OS: Windows
- Server software: PaperMC, managed by server panel
- Tunneling: Built-in tunnel, powered by playit.gg
- Cross-play: Geyser-Spigot + Floodgate
- Domain: `play.yourdomain.com`

### Debugging — What Was Tested

| Test | Result |
|---|---|
| Bedrock (UDP) via tunnel | ✅ Works perfectly |
| Java (TCP) via tunnel, domain or raw IP | ❌ Always fails |
| Local join via `localhost:25565` on host PC | ✅ Works — server itself is healthy |
| Full server log during successful local join | ✅ Clean — plugins loaded, player joined/played/disconnected normally |
| `netstat` — server listening on `0.0.0.0:25565` | ✅ Confirmed |
| Windows Firewall rules for `java.exe` | ✅ Allowed (Public + Private); also fully disabled — no change |
| DNS (A, AAAA, SRV records) for tunnel domain | ✅ Resolve correctly |
| SRV record target | Tunnel host and port |
| Public port open check (canyouseeme.org, portchecker.co) | ✅ Shows open on IPv4 |
| `mcsrvstat.us` external ping check | ❌ "Unknown problem with returned server data" / "Failed to read from socket" |
| Proxy Protocol setting | Set to **None** |
| `server.properties` | `server-ip=` blank, `online-mode=false`, `prevent-proxy-connections=false` |
| Changed local server port | ❌ No change |
| Cloudflare WARP on host PC | ❌ No change |
| Updated DNS to Google (8.8.8.8) + flushed DNS cache | ❌ No change |
| Disabled IPv6 on Windows network adapter | ❌ No change |
| Self-test from second PC on same LAN | ❌ "Connection reset" — anti-portscanner protection |
| **Independent test via Pinggy** (`ssh -p 443 -R0:localhost:25565 tcp@a.pinggy.io`) | ✅ **Friend connected on the first try** |

### Root Cause

The Pinggy test was decisive: with the exact same server, firewall, router, and ISP, a friend connected immediately. This proved that the problem was isolated specifically to the previous TCP tunnel relay.

### Options Considered for a Permanent Free Fix

| Option | Decision |
|---|---|
| Fix tunnel IPv6/region setting directly | ❌ Tried all settings — no change |
| Paid tunnel services | ❌ Ruled out — wanted free only |
| Oracle Cloud Free Tier VPS as TCP relay | ❌ Ruled out — signup verification hurdles |
| Cloudflare Tunnel | ❌ Free tier only proxies HTTP/HTTPS; raw TCP requires paid Spectrum |
| Aternos / free host | ❌ Server sleeps when idle, limited plugin support |
| **Pinggy free tier + auto-restart + auto-DNS update** | ✅ **Chosen — fully working, free, automated** |

---

## How It Works in Production

### Java Edition

**Players connect to:** `play.yourdomain.com` (no port needed)

**How it works:** This script (`minecraft-tunnel-autostart.ps1`) runs continuously on the host PC and:
1. Opens a free Pinggy SSH TCP tunnel pointed at `localhost:25565`
2. Parses the public `tcp://host:port` address Pinggy assigns
3. Automatically updates the DNS SRV record (`_minecraft._tcp.play.yourdomain.com`) via API to point at the new address
4. Hot-swaps to a fresh tunnel every ~55 minutes (before the free-tier 60-minute expiry) with near-zero downtime
5. Repeats indefinitely, surviving PC restarts via Windows Task Scheduler or GUI background mode

### Bedrock Edition

**Players connect to:** `bedrock.yourdomain.com`, port `50909`

**How it works:** Simple static A record in your DNS provider pointing `bedrock` → tunnel IP address for UDP. Bedrock (UDP) tunnels typically remain stable without needing frequent port rotations.

### Current DNS Records (relevant)

| Type | Name | Content | Notes |
|---|---|---|---|
| SRV | `_minecraft._tcp.play` | `0 5 <dynamic port> <dynamic Pinggy host>.` | Auto-updated by this script on every tunnel restart |
| A | `bedrock` | `147.185.221.31` | Static — points at working Bedrock tunnel |
| CNAME | `play` → `whiny-cup.gl.joinmc.link` | *(stale, safe to delete)* | Leftover from the original broken playit Java tunnel; no longer used since the SRV record takes precedence for Java clients |

### Possible Future Improvements

- Auto-start the Squid/Minecraft server itself on boot (not just this tunnel script), for fully hands-off restart recovery
- Migrate server management from Squid to **Crafty Controller** (Docker-based) for a nicer UI — independent of the networking setup, which would remain unchanged
- Delete the stale `play` CNAME record pointing at the old broken playit Java tunnel
- If Squid/playit support ever resolves the TCP relay bug on their end, could optionally revert to the simpler built-in tunnel

---

## License

No license is currently specified. All rights reserved by the repository owner.

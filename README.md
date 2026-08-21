# TheRealNeighbors Minecraft Gateway

A PowerShell script that exposes a locally-running Minecraft server to the internet through a free [Pinggy](https://pinggy.io) TCP tunnel, then automatically keeps your Hostinger DNS SRV record pointed at the current tunnel address. A hot-swap mechanism pre-starts a replacement tunnel before the active one expires, achieving near-zero downtime for players.

---

## Overview

Pinggy free-tier tunnels expire after roughly 60 minutes. Without intervention, the server becomes unreachable every hour. This script solves that by:

1. Opening a Pinggy TCP tunnel to `localhost:<LocalPort>` via SSH.
2. Parsing the dynamically assigned public hostname and port from the tunnel output.
3. Updating the Hostinger DNS SRV record (`_minecraft._tcp.play.therealneighbors.online`) so the domain always resolves to the current tunnel.
4. At the 55-minute mark, starting a second (replacement) tunnel in the background and switching DNS to it before the old one dies.
5. Letting the old tunnel die on its own, with a 10-minute safety kill as a fallback.
6. Repeating indefinitely, logging every action to a daily log file.

---

## Requirements

| Requirement | Notes |
|---|---|
| Windows 10 or 11 | The script uses Win32 console APIs and a Windows mutex |
| PowerShell 5.1 or later | Included in Windows by default |
| OpenSSH client | Built into Windows 10/11; provides the `ssh` command |
| Hostinger DNS API token | Requires access to manage the `therealneighbors.online` zone |
| Minecraft server | Must be listening on the configured local port (default: `25566`) |

No external PowerShell modules are required.

---

## File Structure

```
TheRealNeighborsMinecraftSetup/
├── minecraft-tunnel-autostart.ps1   # Main script
├── .env                             # Secret token storage (not committed to git)
├── .gitignore                       # Excludes .env from version control
└── README.md                        # This file
```

---

## Setup

### 1. Create the `.env` file

The script reads your Hostinger API token from a `.env` file located in the same directory as the script. Create it manually:

```
HostingerToken=YOUR_HOSTINGER_API_TOKEN_HERE
```

The `.env` file is excluded from git via `.gitignore`. Never commit it.

To generate a Hostinger API token, log in to your Hostinger account, go to **Profile > API**, and create a new token with DNS management permissions.

### 2. Ensure your Minecraft server is running

By default the script tunnels port `25566`. Confirm your server is bound to that port before starting the script. To change the port, edit the `$LocalPort` variable near the top of `minecraft-tunnel-autostart.ps1`.

### 3. Run the script

Open PowerShell and run:

```powershell
.\minecraft-tunnel-autostart.ps1
```

If you receive an execution policy error, run:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

---

## Configuration

All user-facing settings are declared at the top of the script under the `CONFIG` section:

| Variable | Default | Description |
|---|---|---|
| `$RootDomain` | `therealneighbors.online` | The root DNS zone managed on Hostinger |
| `$SrvRecordName` | `_minecraft._tcp.play` | The SRV record name within the zone |
| `$LocalPort` | `25566` | The local port your Minecraft server listens on |
| `$Priority` | `0` | SRV record priority field |
| `$Weight` | `5` | SRV record weight field |
| `$TTL` | `60` | DNS TTL in seconds (low value ensures fast propagation) |
| `$HotSwapMinute` | `55` | Minutes elapsed before a replacement tunnel is pre-started |

---

## How It Works

### Tunnel lifecycle

```
Start-Tunnel
    |-- Launches ssh process (Pinggy TCP tunnel)
    |-- Registers async output/error handlers to capture the assigned URL
    |-- Sends blank stdin lines to bypass password prompts
    |-- Waits up to 60 seconds for a tcp://host:port URL in output
    |-- Returns tunnel object (proc, state, handlers)
```

### DNS update

After a successful tunnel start, `Update-HostingerSRV` is called:

1. Sends a DELETE request to remove any existing SRV records of the same name.
2. Waits 2 seconds to allow Hostinger's API to process the deletion.
3. Sends a PUT request to create the new SRV record pointing at the tunnel's hostname and port.
4. Retries the PUT up to 3 times on failure, with 5-second delays between attempts.

### Hot-swap

When the active tunnel has been running for `$HotSwapMinute` minutes (default 55):

1. A second tunnel is started in parallel.
2. DNS is immediately updated to point at the new tunnel.
3. The old tunnel object is kept in memory and monitored. It is cleaned up when Pinggy terminates it naturally, or forcibly after 10 minutes.
4. The monitoring loop switches to the new tunnel seamlessly.

### Watchdog

If a tunnel is still alive after 75 minutes (a fallback for cases where Pinggy does not terminate it on schedule), the script force-kills the process and begins a new cycle.

### Duplicate instance guard

A named Windows mutex (`Global\TRN_MinecraftGateway`) prevents two instances of the script from running simultaneously. If a second instance is launched, it exits immediately with an error message.

---

## Logging

Logs are written to:

```
%USERPROFILE%\TRN_Gateway_Logs\gateway_YYYY-MM-DD.log
```

A new log file is created each day. All tunnel events, DNS operations, hot-swap actions, and errors are recorded with timestamps.

---

## Players: How to Connect

Players connect using the domain name rather than a raw IP address. Because the script maintains the SRV record, players only ever need to add the server using:

```
play.therealneighbors.online
```

No port number is required in the Minecraft client when a valid SRV record is present. The low TTL (60 seconds) means DNS changes propagate to players within about a minute of a hot-swap.

---

## Troubleshooting

**Script exits with "HostingerToken not found"**
Create a `.env` file in the same directory as the script containing `HostingerToken=YOUR_TOKEN`.

**Tunnel fails to start / No URL detected after 60 seconds**
Confirm the `ssh` command is available (`ssh -V` in a terminal). The OpenSSH client must be installed. Also verify the machine has outbound access on port 443.

**DNS update fails with 4xx errors**
Verify the Hostinger API token has write permissions for the `therealneighbors.online` zone and has not expired.

**Console freezes when clicked**
The script disables QuickEdit mode on startup to prevent this. If the terminal was opened before the script ran and QuickEdit was already active, right-click the title bar, choose Properties, and uncheck QuickEdit Mode.

**Another instance is already running**
Close the other PowerShell window running the script, or kill the existing `ssh` processes via Task Manager, then relaunch.

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
- Host OS: Windows (Philippines, Parasat ISP)
- Server software: PaperMC 26.1.2, managed by SquidServers v0.9.5
- Tunneling: SquidServers' built-in tunnel, powered by playit.gg
- Cross-play: Geyser-Spigot + Floodgate (working fine)
- Domain: `play.therealneighbors.online` (Hostinger), plus the tunnel-provided `whiny-cup.gl.joinmc.link`

### Debugging — What Was Tested

| Test | Result |
|---|---|
| Bedrock (UDP) via tunnel | ✅ Works perfectly |
| Java (TCP) via tunnel, domain or raw IP | ❌ Always fails |
| Local join via `localhost:25565` on host PC | ✅ Works — server itself is healthy |
| Full server log during successful local join | ✅ Clean — all 14 plugins loaded, player joined/played/disconnected normally |
| `netstat` — server listening on `0.0.0.0:25565` | ✅ Confirmed |
| Windows Firewall rules for `java.exe` / Squid | ✅ Allowed (Public + Private); also fully disabled — no change |
| DNS (A, AAAA, SRV records) for tunnel domain | ✅ Resolve correctly |
| SRV record target | `whiny-cup.gl.at.ply.gg`, port `50909` (TCP) |
| Public port open check (canyouseeme.org, portchecker.co) | ✅ Shows open on IPv4 |
| `mcsrvstat.us` external ping check | ❌ "Unknown problem with returned server data" / "Failed to read from socket" — connects but gets invalid data |
| Proxy Protocol setting | Set to **None** in playit dashboard; `paper-global.yml` also expects none — no mismatch |
| `server.properties` | `server-ip=` blank, `online-mode=false`, `prevent-proxy-connections=false` — all normal |
| Changed local + tunnel port 25565 → 25566 | ❌ No change |
| Cloudflare WARP (Traffic and DNS mode) on host PC | ❌ No change |
| Updated DNS to Google (8.8.8.8) + flushed DNS cache | ❌ No change |
| Disabled IPv6 on Windows network adapter | ❌ No change |
| Self-test from second PC on same LAN | ❌ "Connection reset" — but playit support confirmed this is **expected** (anti-portscanner protection), not a real signal |
| playit.gg agent "Allow IPv6" toggle → set to IPv4-only | ❌ No change |
| playit.gg agent Region → switched from Automatic to Asia | ❌ No change |
| **Independent test via Pinggy** (`ssh -p 443 -R0:localhost:25566 tcp@a.pinggy.io`), bypassing Squid/playit entirely | ✅ **Friend connected on the first try** |

### Root Cause

The Pinggy test was decisive: with the exact same server, firewall, router, and ISP, a friend connected immediately. This proved that **the problem was isolated specifically to the playit/Squid Java TCP tunnel** — not the server, not Windows Firewall, not the router, not the ISP.

Squid/playit support's diagnosis: most likely a broken IPv6 routing path or a broken relay in playit's TCP tunnel infrastructure for this specific account. TCP and UDP are handled as separate tunnel instances on playit's network, which explains why Bedrock (UDP) worked while Java (TCP) didn't. No fix was available from the dashboard side; support ticket remains open.

### Options Considered for a Permanent Free Fix

| Option | Decision |
|---|---|
| Fix playit IPv6/region setting directly | ❌ Tried all settings — no change |
| Pinggy Pro (~$3/month) | ❌ Ruled out — wanted free only |
| Oracle Cloud Free Tier VPS as TCP relay via `socat` | ❌ Ruled out — Oracle signup verification kept failing |
| Cloudflare Tunnel | ❌ Free tier only proxies HTTP/HTTPS; raw TCP (Minecraft Java) requires paid Spectrum or every player installing WARP |
| Aternos / free host | ❌ Server sleeps when idle, limited/no custom plugin support (would break GrimAC, GriefPrevention, CoreProtect, AuraSkills, SkinsRestorer, LevelledMobs, etc.) |
| Pumpkin (Rust-based server software) | ❌ Not a hosting/tunnel solution; early development; incompatible with existing Bukkit/Spigot plugin stack |
| **Pinggy free tier + auto-restart + auto-DNS update** | ✅ **Chosen — fully working, free, automated** |

---

## Current Production Setup

### Java Edition

**Players connect to:** `play.therealneighbors.online` (no port needed)

**How it works:** This script (`minecraft-tunnel-autostart.ps1`) runs continuously on the host PC and:
1. Opens a free Pinggy SSH TCP tunnel pointed at `localhost:25566`
2. Parses the public `tcp://host:port` address Pinggy assigns
3. Automatically updates the Hostinger SRV record (`_minecraft._tcp.play.therealneighbors.online`) via the Hostinger API to point at the new address
4. Hot-swaps to a fresh tunnel every ~55 minutes (before the free-tier 60-minute expiry) with near-zero downtime
5. Repeats indefinitely, surviving PC restarts via Windows Task Scheduler

**Auto-start on boot:** Configured via Windows Task Scheduler to run the script silently at startup (hidden PowerShell window, highest privileges).

### Bedrock Edition

**Players connect to:** `bedrock.therealneighbors.online`, port `50909`

**How it works:** Simple static A record in Hostinger pointing `bedrock` → `147.185.221.31` — the stable, working Squid/playit Bedrock UDP tunnel. No changes were ever needed here; Bedrock (UDP) was never broken.

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

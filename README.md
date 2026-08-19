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

## License

No license is currently specified. All rights reserved by the repository owner.

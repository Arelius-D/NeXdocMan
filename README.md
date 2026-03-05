# NeXdocMan: Intelligent Docker & Compose Automation 🐳

> **Version:** v2.0.1  
> **Core Philosophy:** "Deploy, Maintain, and Prune—Silently and Cleanly."

## 1. What is NeXdocMan?

NeXdocMan is not just a standard installation script. It is an **intelligent, self-maintaining manager** for Docker and Docker Compose on Debian-based systems.

Unlike traditional bash scripts that blindly run `apt install` and walk away, NeXdocMan operates on a robust, state-aware architecture. It prepares your system, smartly resolves conflicting legacy packages, actively monitors for dependency updates, and maintains an automated, cron-powered clean-up cycle to ensure your Docker environment never succumbs to container bloat.

It is designed for environments (Homelabs, Remote Servers, CI/CD Nodes) where you need a premium, set-and-forget orchestration layer for your Docker engine.

---

## 2. Why Use NeXdocMan? (The Logic)

NeXdocMan solves three critical problems inherent in manual Docker management:

### A. The "Bloat" Filter (Intelligent System Pruning)

Active Docker environments accumulate dead containers, dangling images, and orphaned volumes rapidly.

- **The Problem:** Over time, your storage fills up with gigabytes of unused Docker caching and halted networks.
- **The NeXdocMan Solution:** Through the fully configurable `CLEANUP_CRON` protocol, NeXdocMan natively integrates into your system's crontab. It wakes up intelligently, executes a comprehensive `docker system prune -a --volumes -f`, logs the exact amount of reclaimed space, and goes back to sleep. You save gigabytes of storage over time without you ever lifting a finger.

### B. High-Visibility Logging (The "Black Box" Fix)

Setup scripts usually spit output into the terminal and vanish. If an installation fails or a cron job errors out during the night, you have no idea why.

- **The NeXdocMan Solution:** Every action—whether a manual TUI sequence or a silent cron execution—is strictly logged to `/var/log/NeXdocMan/nexdocman.log`. Through the customizable `[LOG_LEVEL]` and `[LOGPRUNE]` mechanisms, NeXdocMan acts as its own auditor, logging specific events and automatically deleting events older than your defined threshold to preserve disk space.

### C. True Agnostic Execution (Dynamic Intelligence)

NeXdocMan is completely self-aware and dynamic.

- **The NeXdocMan Solution:** It checks for `curl` vs `wget`, resolving its own dependencies if neither are found. It evaluates your current user groups, securely injecting them into the `docker` group, and tests the daemon connection natively. It acts as a single, global binary.

---

## 3. Core Architecture

NeXdocMan follows a strict execution pipeline to ensure system integrity:

1. **Self-Deploying Payload:** When you download the utility, it instantly installs itself to your global system binaries (`/usr/local/bin/nexdocman`) and **deletes the downloaded file** to keep your workspace flawlessly clean.
2. **Pre-Flight Scans:** Validates OS dependencies and completely purges legacy/conflicting Docker packages (`docker.io`, `podman-docker`, `runc`) to ensure a pure installation path.
3. **Dynamic Installation:** Natively routes the official Docker socket via `curl` or `wget`, installing both Docker and Docker Compose.
4. **Environment Injection:** Dynamically pushes your `$USER` into the `docker` group and performs an active system daemon test (`hello-world`) to guarantee stability.
5. **Configuration Generation:** Creates a heavily documented `.cfg` file in `/usr/local/lib/nexdocman/`, defining your automation boundaries.
6. **Cron Implantation:** Reads your config file and securely injects a system-silent cron job dedicated to pruning your environment on schedule.
7. **Clean Purging & Removal:** Offers surgical precision removal. You can uninstall just the utility (`--remove-utility`), or completely nuke the Docker engine, its networks, and its volumes (`--purge`).

---

## 4. Configuration Guide

NeXdocMan is heavily controlled via `nexdocman.cfg`, auto-generated in `/usr/local/lib/nexdocman/` upon initial deployment.

### `[ENABLE_AUTO_CLEANUP]` & `[CLEANUP_CRON]`

Controls the automated system pruning.

**How it works:**

- `ENABLE_AUTO_CLEANUP`: Set to `true` to activate the automated scheduled Docker cleanup.
- `CLEANUP_CRON`: Standard cron syntax. Dictates exactly when the prune module initiates.

**Examples:**

```ini
# Every 2 days at 3:00 AM
CLEANUP_CRON="0 3 */2 * *"

# Every Sunday at 2:00 AM
CLEANUP_CRON="0 2 * * 0"

# Every day at 4:30 AM
CLEANUP_CRON="30 4 * * *"
```

---

### `[LOG_LEVEL]` (Verbosity Control)

**Control what gets written to `nexdocman.log`.**

```ini
LOG_LEVEL="INFO"
```

- **Options:** `DEBUG`, `INFO`, `WARNING`, `ERROR`
- **`INFO`**: Logs normal operational messages (installations, prunes, space reclaimed). Provides a solid, readable history.
- **`DEBUG`**: Logs verbose engine processes. (Recommended only for deep troubleshooting).
- **`ERROR`**: Silent mode. Only logs if something breaks.

---

### `[LOGPRUNE]` (Log File Management)

**Automatically clean old entries from `nexdocman.log` using a high-speed chronological `awk` engine.**

```ini
LOGPRUNE_ENABLED=true
LOGPRUNE_MAX_AGE_DAYS=7
```

- **`LOGPRUNE_ENABLED=true`**: Active. NeXdocMan will delete log entries older than the specified age during its cleanup cycle.
- **`LOGPRUNE_MAX_AGE_DAYS=7`**: Keep only the last 7 days of logs.

**Why this exists:**
If you run frequent prunings or set your log level to `DEBUG`, your log file could grow indefinitely. This guarantees your logs remain cleanly rotated and highly relevant, conserving system storage automatically.

---

## 5. Installation & First Run

### Quick Deployment

To get started, you must **deploy** the utility. You download a temporary script payload, and execute it with the `--deploy` flag.

**What happens next?**

1. The script initializes its configuration and log directories.
2. It installs itself permanently into your system PATH.
3. **It deletes the temporary downloaded payload.**

_From that point forward, you simply type `nexdocman` anywhere in your terminal. You do not need the `.sh` file anymore._

**Option A: Using curl**

```bash
curl -L https://github.com/Arelius-D/NeXdocMan/releases/download/v2.0.1/NeXdocMan.tar.gz -o NeXdocMan.tar.gz && \
tar -xzvf NeXdocMan.tar.gz && cd NeXdocMan && \
sudo chmod +x nexdocman.sh && sudo ./nexdocman.sh -d && \
cd .. && rm -rf NeXdocMan NeXdocMan.tar.gz
```

**Option B: Using wget**

```bash
wget https://github.com/Arelius-D/NeXdocMan/releases/download/v2.0.1/NeXdocMan.tar.gz && \
tar -xzvf NeXdocMan.tar.gz && cd NeXdocMan && \
sudo chmod +x nexdocman.sh && sudo ./nexdocman.sh -d && \
cd .. && rm -rf NeXdocMan NeXdocMan.tar.gz
```

---

## 6. Usage & CLI Flags

Once deployed, NeXdocMan is completely flexible. Run it through its premium UI, or trigger it blindly via flags.

### Interactive TUI Mode:

```bash
nexdocman
```

```text
==================================================
 🐧 NeXdocMan - Docker Manager (v2.0.1)
==================================================

 [Core Operations]
   1. Install Docker & Docker Compose
   2. Check and Update Docker & Docker Compose

 [Maintenance & Automation]
   3. Run Automated System Cleanup (Prune)
   4. Configure Automated Cleanup Schedule (Cron)

 [Advanced & Destructive]
   5. Purge ALL Docker Installations & Volumes

   0. Exit
--------------------------------------------------
Choose an option [0-5]:
```

### Automation CLI Mode:

```text
USAGE:
  nexdocman [OPTIONS]

OPTIONS:
  [General]
  -h, --help           Show this comprehensive help message and exit.
  -v, --version        Show utility and script version.
  -y, --yes            Auto-confirm all prompts (Non-interactive mode).
  -V, --verbose        Run operations with verbose output to terminal.

  [Deployment & Removal]
  -d, --deploy         Initialize directories, config, and deploy NeXdocMan globally.
  -r, --remove         Uninstall NeXdocMan, its logs, configs, and schedules entirely.

  [Docker Operations]
  -i, --install        Install Docker and Docker Compose and set up groups.
  -m, --manage         Check for Docker and Compose updates and apply them.
  -c, --cleanup        Manually trigger a deep Docker system prune.
  -C, --configure-cron Reload the automated prune schedule from nexdocman.cfg.
  -p, --purge          Completely uninstall Docker, Compose, and wipe all data.
```

**Examples:**

```bash
sudo nexdocman -d              # First-time setup on a new server
sudo nexdocman -i -y           # Install Docker cleanly with no prompts
nexdocman -c                   # Trigger an immediate runtime prune
nexdocman -r -y                # Uninstall NeXdocMan but leave Docker running
sudo nexdocman -p -y           # Nuke and pave the entire Docker system silently
```

---

## 7. Troubleshooting & FAQ

### Q: NeXdocMan says Docker is installed, but my user is getting "permission denied" errors when running docker commands.

**A:** NeXdocMan safely adds your current user to the `docker` group automatically during `--install-docker`. However, Linux requires your session to refresh for group changes to take effect. Either run `newgrp docker`, or simply close the terminal and reconnect via SSH. You never need to run containers as `root`.

### Q: What exactly does `--purge` delete?

**A:** Everything. It stops the daemon, uninstalls the core `docker-ce` binaries, and actively recursively deletes `/var/lib/docker/`, `/var/lib/containerd/`, and `~/.docker`. Only use this if you want a complete environment wipe. Container volumes stored in `/var/lib/docker` will be eradicated.

### Q: What exactly does `-r, --remove` delete?

**A:** It removes NeXdocMan completely, but **leaves Docker safely running**. It deletes the `nexdocman` binary, the `/usr/local/lib/nexdocman` config, the `/var/log/NeXdocMan` log folder, and strips the automation schedules from your `crontab`.

### Q: How do I know if the automated cleanup is working?

**A:** Check the execution logs natively via:

```bash
cat /var/log/NeXdocMan/nexdocman.log | grep "PRUNE DETAILED"
```

You will see exactly how many items were untagged and deleted, and the exact megabytes (or gigabytes) of space reclaimed.

---

#### ⭐ Like This Utility?

🌟 [Star it on GitHub!](https://github.com/Arelius-D/NeXdocMan)  
🔔 **Stay updated** — [Watch for notifications](https://github.com/Arelius-D/NeXdocMan)  
💬 **Share ideas**: [GitHub Discussions](https://github.com/Arelius-D/NeXdocMan/discussions)  
🐞 **Found a bug?** [Report it here](https://github.com/Arelius-D/NeXdocMan/issues)  
💖 **Any form of contributions or donations is immensely appreciated.** [Sponsor here](https://github.com/sponsors/Arelius-D)

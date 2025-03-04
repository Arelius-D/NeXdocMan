# 🐳 NeXdocMan - Docker and Docker Compose Provisioning
**Version:** 1.0.0 | **License:** MIT 

**Description:**
Streamlined and lightweight shell-based utility for unifying Docker and Docker Compose installations and initial configuration on any Debian-based systems. Whether you need to install, update, or even remove Docker and Docker Compose without a trace, NeXdocMan simplifies the process with both minimalist TUI or direct CLI execution.

## 🧠 Why NeXdocMan?
Takes the hassle out of setting things up by ensuring a smooth and reliable experience every time.

### 📌 Features
- **One-command Setup** – Install Docker and Docker Compose effortlessly.
- **User Management** – Automatically adds the current user to the Docker group.
- **Seamless Workflow** – Eliminates the need to log in and out after installation.
- **Automated Updates** – Check for and apply Docker updates.
- **Safe Uninstallation** – Cleanly purge Docker and related components if needed.
- **Interactive & CLI Modes** – Use an interactive menu or command-line flags.
- **Logging & Verbose Output** – Detailed logs for tracking actions and executions.

### 📦 Installation

#### Using `wget`: 
```bash
wget https://github.com/Arelius-D/NeXdocMan/releases/download/v1.0.0/NeXdocMan.tar.gz && \
tar -xzvf NeXdocMan.tar.gz && \
cd NeXdocMan && \
sudo chmod +x nexdocman.sh && \
sudo ./nexdocman.sh --initiate && \
cd .. && \
rm -rf NeXdocMan NeXdocMan.tar.gz
```

#### Using `curl`:  

```bash
curl -L https://github.com/Arelius-D/NeXdocMan/releases/download/v1.0.0/NeXdocMan.tar.gz -o NeXdocMan.tar.gz && \
tar -xzvf NeXdocMan.tar.gz && \
cd NeXdocMan && \
sudo chmod +x nexdocman.sh && \
sudo ./nexdocman.sh --initiate && \
cd .. && \
rm -rf NeXdocMan NeXdocMan.tar.gz
```

### 🖥️ Usage
To access the interactive menu (TUI):
```bash
nexdocman
```
Or go full CLI:
```bash
nexdocman --install     # Installs Docker & Compose
nexdocman --manage      # Checks for updates
nexdocman --purge       # Completely removes Docker
```


### 🧩 Components
- `nexdocman.sh` – The main script that manages execution and user interaction.
- `setup.sh` – Installs Docker & Docker Compose.
- `check_update.sh` – Checks for updates and prompts for upgrades.
- `purge.sh` – Removes Docker, cleans up files, and resets the system.

#### ⭐ Like This Utility?

🌟 [Star it on GitHub!](https://github.com/Arelius-D/NeXdocMan)\
🔔 **Stay updated** — [Watch for notifications](https://github.com/Arelius-D/NeXdocMan)\
💬 **Share ideas**: [GitHub Discussions](https://github.com/Arelius-D/NeXdocMan/discussions)\
🐞 **Found a bug?** [Report it here](https://github.com/Arelius-D/NeXdocMan/issues)\
💖 **Any form of contributions or donations is immensely appreciated.** [Sponsor here](https://github.com/sponsors/Arelius-D)
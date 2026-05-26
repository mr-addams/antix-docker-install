# Docker Installation Script for antiX Linux

![Platform](https://img.shields.io/badge/platform-antiX%20Linux%2023.2-blue)
![Debian](https://img.shields.io/badge/debian-12%20bookworm-red)
![License](https://img.shields.io/badge/license-MIT-green)
![Init System](https://img.shields.io/badge/init-sysVinit%20ONLY-orange)
![Docker](https://img.shields.io/badge/docker-latest-2496ED?logo=docker)
![Maintenance](https://img.shields.io/badge/maintained-yes-brightgreen)

Complete Docker installation script for **antiX Linux 23.2 with sysVinit** (and other Debian-based systems using sysVinit).

## ⚠️ Important: sysVinit Only

**This script is specifically designed for sysVinit-based systems ONLY.**

- ✅ **Works with**: antiX Linux with **sysVinit** init system
- ❌ **NOT compatible with**: antiX runit version, systemd-based systems

antiX Linux comes in two init system variants:
- **sysVinit** - ✅ Use this script
- **runit** - ❌ Do NOT use this script (requires different init configuration)

To check your init system:
```bash
ps -p 1 -o comm=
# Output should be: init (for sysVinit)
# If output is: runit or systemd - DO NOT use this script
```

## Overview

This script performs a complete Docker installation on antiX Linux, which uses sysVinit instead of systemd. It handles all the complexities of Docker installation on non-systemd systems, including proper init script creation and service management.

## Features

- ✅ Complete cleanup of any existing Docker installations
- ✅ Fresh installation of latest Docker CE with all plugins
- ✅ Custom init script for sysVinit systems
- ✅ Automatic service configuration and autostart setup
- ✅ Docker Compose plugin included
- ✅ Docker Buildx plugin included
- ✅ Comprehensive installation verification
- ✅ User permission configuration

## System Requirements

- antiX Linux 23.2 (based on Debian 12 Bookworm)
- Root access
- Internet connection
- Minimum 512 MB RAM (recommended)

## Compatibility

**This script is ONLY for sysVinit-based systems.**

| Distribution | Init System | Docker Source | Status |
|---|---|---|---|
| antiX Linux 23.x | sysVinit | Docker Inc repo (`/usr/bin/dockerd`) | ✅ Tested |
| Devuan 4/5+ | sysVinit (or fork) | Debian package / self-built (`/usr/sbin/dockerd`) | ✅ Tested (fixes #1) |
| MX Linux | sysVinit | Docker Inc repo | ✅ Compatible |
| Debian 12 Bookworm | sysVinit (if configured) | Docker Inc repo | ✅ Compatible |
| antiX Linux 23.x | **runit** | N/A | ❌ NOT compatible |
| Any distribution | **systemd** | Docker official method recommended | ❌ NOT compatible |

### How to check your init system:

```bash
# Check init system
ps -p 1 -o comm=

# Expected output for compatibility:
# init  ← sysVinit (✅ Compatible)

# If you see these, DO NOT use this script:
# runit ← runit init system (❌ Not compatible)
# systemd ← systemd (❌ Not compatible)
```

**Note for runit users**: This script creates init scripts for `/etc/init.d/` which are sysVinit-specific. For runit-based antiX, you need different service management approach using runit's service directory structure.

## Installation

### Quick Install

```bash
# Download the script
wget https://raw.githubusercontent.com/mr-addams/antix-docker-install/main/antix-docker-install.sh

# Make it executable
chmod +x antix-docker-install.sh

# Run as root
sudo ./antix-docker-install.sh
```

### Manual Installation

1. Clone this repository:
```bash
git clone https://github.com/mr-addams/antix-docker-install.git
cd antix-docker-install
```

2. Make the script executable:
```bash
chmod +x antix-docker-install.sh
```

3. Run the script as root:
```bash
sudo ./antix-docker-install.sh
```

## What the Script Does

### 1. **Complete Cleanup**
   - Stops all Docker processes
   - Removes all existing Docker packages (including old versions)
   - Unmounts Docker filesystems
   - Cleans up configuration files and data directories
   - Removes old repositories and GPG keys

### 2. **Fresh Installation**
   - Installs required dependencies
   - Adds official Docker repository
   - Installs Docker CE and all plugins:
     - docker-ce
     - docker-ce-cli
     - containerd.io
      - docker-buildx-plugin
      - docker-compose-plugin

### 3. **System Configuration**
   - Creates custom init script for sysVinit
   - Configures Docker daemon settings
   - Sets up autostart with update-rc.d
   - Configures user permissions

### 4. **Verification**
   - Tests init script functionality
   - Verifies Docker daemon startup
   - Checks Docker CLI
   - Tests Docker Compose
   - Runs hello-world container

## Usage

### Service Management

After installation, manage Docker using standard init commands:

```bash
# Start Docker
sudo /etc/init.d/docker start

# Stop Docker
sudo /etc/init.d/docker stop

# Restart Docker
sudo /etc/init.d/docker restart

# Check status
sudo /etc/init.d/docker status
```

### Verification Commands

```bash
# Check Docker version
docker --version

# Check Docker Compose
docker compose version

# Run test container
docker run hello-world

# List running containers
docker ps

# View system info
docker info
```

### User Permissions

The script automatically adds your user to the `docker` group. To apply group changes:

```bash
# Log out and log back in
# OR force group refresh
newgrp docker
```

After this, you can run Docker commands without `sudo`.

## Troubleshooting

### Docker won't start

1. Check logs:
```bash
cat /var/log/docker.log
```

2. Check for running processes:
```bash
ps aux | grep dockerd
```

3. Verify socket exists:
```bash
ls -la /var/run/docker.sock
```

4. Try manual cleanup and restart:
```bash
sudo killall -9 dockerd
sudo rm -f /var/run/docker.sock /var/run/docker.pid
sudo /etc/init.d/docker start
```

### Permission denied errors

Ensure your user is in the docker group:
```bash
groups $USER
```

If docker group is missing, run:
```bash
sudo usermod -aG docker $USER
newgrp docker
```

### "Device or resource busy" during cleanup

The script handles this automatically by unmounting Docker filesystems. If you encounter this manually:
```bash
sudo umount $(mount | grep '/var/lib/docker' | awk '{print $3}' | sort -r)
```

### Container startup issues

Check system resources:
```bash
free -h
df -h
```

Verify Docker daemon is running:
```bash
sudo /etc/init.d/docker status
docker info
```

## Configuration

Docker configuration is stored in `/etc/docker/daemon.json`:

```json
{
  "debug": false,
  "storage-driver": "overlay2",
  "exec-opts": ["native.cgroupdriver=cgroupfs"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

You can modify this file and restart Docker to apply changes:
```bash
sudo /etc/init.d/docker restart
```

## Uninstallation

To completely remove Docker:

```bash
# Stop Docker
sudo /etc/init.d/docker stop

# Remove packages
sudo apt-get remove --purge docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Remove data and configuration
sudo rm -rf /var/lib/docker
sudo rm -rf /etc/docker
sudo rm -f /etc/init.d/docker
sudo rm -f /var/run/docker.sock

# Remove user from docker group
sudo deluser $USER docker

# Clean up
sudo apt-get autoremove
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Guidelines

- Test changes on antiX Linux 23.2
- Maintain compatibility with sysVinit
- Update README if adding new features
- Follow existing code style

## Known Issues

- First container startup may be slow due to image downloads
- Some Docker features requiring systemd may not work
- **This script will NOT work on antiX runit version** - it requires sysVinit

## License

MIT License

Copyright (c) 2026 antiX Docker Installation Script Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Credits

Created for the antiX Linux community to simplify Docker installation on non-systemd systems.

## Support

- **Issues**: [Report bugs via GitHub Issues](https://github.com/mr-addams/antix-docker-install/issues)
- **Discussions**: [GitHub Discussions](https://github.com/mr-addams/antix-docker-install/discussions)
- **antiX Forum**: https://www.antixforum.com/
- **Docker Documentation**: https://docs.docker.com/

## Changelog

### Version 1.1.4
- Final shellcheck: zero warnings, clean syntax pass

### Version 1.1.3
- README: compatibility table added (antiX, Devuan, MX Linux, Debian — tested/supported/not compatible)

### Version 1.1.2
- Auto-detection of Linux distribution (antiX / Devuan / MX Linux / generic Debian) at script start

### Version 1.1.1
- Safe GPG key download: curl no longer piped directly to gpg — downloaded to temp file with verification (exit code + non-empty check)

### Version 1.1.0
- Cross-distro support: now works on antiX, Devuan, MX Linux and other Debian forks with sysVinit
- Auto-detection of dockerd path via `command -v` with fallback chain (fixes Devuan compatibility)
- Removed `docker-model-plugin` from default install (unnecessary AI dependencies on low-resource distros)
- Added `set -euo pipefail` with proper error handling guards
- Fixed error message: `docker-full-install.sh` → `antix-docker-install.sh`
- Fixed shellcheck warnings (SC2046, SC2086)
- Updated README: compatibility table, removed Docker Model references

### Version 1.0.0
- Initial release
- Full Docker CE installation support
- SysVinit integration
- Automatic cleanup and verification
- All official plugins included

---

**Note**: This script is specifically designed for antiX Linux and similar sysVinit-based systems. For systemd-based distributions, use the official Docker installation methods.

#!/bin/bash
set -euo pipefail

SCRIPT_VERSION="1.1.2"

# Root check
if [ "$EUID" -ne 0 ]; then 
    echo "Run as root: sudo bash antix-docker-install.sh"
    exit 1
fi

echo "=== COMPLETE DOCKER INSTALLATION FOR ANTIX (v$SCRIPT_VERSION) ==="

# Определение дистрибутива — antiX, Devuan, MX Linux или generic Debian
DISTRO=""
if [ -f /etc/antix-version ]; then
    DISTRO="antiX"
elif [ -f /etc/devuan-version ]; then
    DISTRO="Devuan"
elif command -v lsb_release >/dev/null 2>&1; then
    DISTRO=$(lsb_release -is 2>/dev/null || echo "Debian")
else
    DISTRO="Debian"
fi
echo "Detected distribution: $DISTRO"
echo ""

# 1. Kill all Docker processes (but not this script!)
echo "1. Stopping all Docker processes..."
# Kill only exact Docker daemon processes, not scripts
killall -9 dockerd 2>/dev/null || true
killall -9 containerd 2>/dev/null || true
killall -9 docker-proxy 2>/dev/null || true
killall -9 containerd-shim 2>/dev/null || true
# Alternative method: kill by full path
pkill -9 -f 'dockerd' 2>/dev/null || true
pkill -9 -f 'containerd' 2>/dev/null || true
sleep 3

# 2. Complete cleanup
echo "2. Complete cleanup of Docker files..."
rm -f /var/run/docker.sock /var/run/docker.pid
rm -f /etc/init.d/docker
update-rc.d docker remove 2>/dev/null || true
rm -rf /etc/docker
rm -rf /var/run/docker
rm -f /var/log/docker.log
rm -f /usr/local/bin/docker-compose

# Unmount all Docker filesystems before deleting
echo "2a. Unmounting Docker filesystems..."
umount "$(mount | grep '/var/lib/docker' | awk '{print $3}' | sort -r)" 2>/dev/null || true
umount "$(mount | grep '/var/lib/containerd' | awk '{print $3}' | sort -r)" 2>/dev/null || true
sleep 2

# Now safe to remove directories
echo "2b. Removing Docker data directories..."
rm -rf /var/lib/docker
rm -rf /var/lib/containerd

# 3. Remove all Docker packages (including old versions)
echo "3. Removing all Docker packages..."
apt-get remove -y --purge \
    docker \
    docker-engine \
    docker.io \
    docker-ce \
    docker-ce-cli \
    docker-ce-rootless-extras \
    docker-scan-plugin \
    containerd \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    runc 2>/dev/null || true

apt-get autoremove -y --purge || true
apt-get autoclean || true

# 4. Clean repositories
echo "4. Cleaning Docker repositories..."
rm -f /etc/apt/sources.list.d/docker.list 
rm -f /etc/apt/sources.list.d/docker.list.save
rm -rf /etc/apt/keyrings/docker.gpg* 
rm -rf /usr/share/keyrings/docker*
apt-get update || true

# 5. Install dependencies
echo "5. Installing dependencies..."
apt-get install -y ca-certificates curl gnupg lsb-release

# 6. Add Docker repository
echo "6. Adding Docker repository..."
install -m 0755 -d /etc/apt/keyrings

# Безопасная загрузка GPG-ключа — через временный файл с проверкой
TEMP_KEY=$(mktemp)
if ! curl -fsSL https://download.docker.com/linux/debian/gpg -o "$TEMP_KEY"; then
    echo "ERROR: Failed to download Docker GPG key. Check internet connection."
    rm -f "$TEMP_KEY"
    exit 1
fi
if [ ! -s "$TEMP_KEY" ]; then
    echo "ERROR: Downloaded GPG key is empty."
    rm -f "$TEMP_KEY"
    exit 1
fi
gpg --dearmor -o /etc/apt/keyrings/docker.gpg "$TEMP_KEY"
rm -f "$TEMP_KEY"
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update

# 7. Install Docker with all plugins
echo "7. Installing Docker with all plugins..."
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# 8. Create init script for antiX
echo "8. Creating init script for antiX..."

cat > /etc/init.d/docker << 'EOF'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          docker
# Required-Start:    $local_fs $remote_fs
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Docker daemon
### END INIT INFO

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
# Автодетект пути dockerd — разные дистрибутивы кладут его в разные места
DOCKERD=""
for d in $(command -v dockerd 2>/dev/null || true) /usr/bin/dockerd /usr/sbin/dockerd; do
    if [ -x "$d" ]; then
        DOCKERD="$d"
        break
    fi
done
if [ -z "$DOCKERD" ]; then
    echo "ERROR: dockerd not found. Is Docker installed?"
    exit 1
fi
PIDFILE=/var/run/docker.pid
SOCKET=/var/run/docker.sock
LOGFILE=/var/log/docker.log

start() {
    echo -n "Starting Docker daemon: "
    
    # FULL cleanup before start
    killall -9 dockerd 2>/dev/null || true
    killall -9 containerd-shim 2>/dev/null || true
    pkill -9 -f '/usr/bin/dockerd' 2>/dev/null || true
    sleep 2
    
    # Remove old files
    rm -f $SOCKET 2>/dev/null
    rm -f $PIDFILE 2>/dev/null
    
    # Check if somehow still running
    if pgrep -x dockerd > /dev/null; then
        echo "already running."
        return 0
    fi
    
    # Start dockerd with --pidfile option so IT manages the PID file
    nohup $DOCKERD --pidfile=$PIDFILE >> $LOGFILE 2>&1 &
    
    # Wait for PID file creation (dockerd creates it)
    local count=0
    while [ $count -lt 30 ]; do
        if [ -f $PIDFILE ] && [ -S $SOCKET ]; then
            local pid=$(cat $PIDFILE)
            if kill -0 $pid 2>/dev/null; then
                echo "done (PID: $pid)."
                return 0
            fi
        fi
        
        sleep 1
        count=$((count + 1))
    done
    
    echo "failed!"
    echo "=== Last 30 lines of log ==="
    tail -30 $LOGFILE 2>/dev/null || echo "No log file"
    return 1
}

stop() {
    echo -n "Stopping Docker daemon: "
    
    if [ -f $PIDFILE ]; then
        local pid=$(cat $PIDFILE)
        if kill -0 $pid 2>/dev/null; then
            kill $pid 2>/dev/null
            
            # Wait for termination (up to 10 seconds)
            local count=0
            while [ $count -lt 10 ]; do
                if ! kill -0 $pid 2>/dev/null; then
                    break
                fi
                sleep 1
                count=$((count + 1))
            done
            
            # If still alive - force kill
            if kill -0 $pid 2>/dev/null; then
                kill -9 $pid 2>/dev/null
                sleep 2
            fi
        fi
    fi
    
    # Additional cleanup - kill ALL dockerd processes
    killall -9 dockerd 2>/dev/null || true
    killall -9 containerd-shim 2>/dev/null || true
    pkill -9 -f '/usr/bin/dockerd' 2>/dev/null || true
    
    # Wait for processes to fully terminate
    sleep 2
    
    # Clean up files
    rm -f $SOCKET 2>/dev/null
    rm -f $PIDFILE 2>/dev/null
    
    echo "done."
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 5
        start
        ;;
    status)
        if [ -f $PIDFILE ]; then
            local pid=$(cat $PIDFILE)
            if kill -0 $pid 2>/dev/null; then
                echo "docker is running (PID: $pid)"
                exit 0
            else
                echo "docker is not running (but PID file exists)"
                exit 1
            fi
        else
            echo "docker is not running"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
EOF

chmod +x /etc/init.d/docker

# 9. Create configuration (without hosts in daemon.json!)
echo "9. Creating Docker configuration..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
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
EOF

# 10. Setup autostart
echo "10. Setting up autostart..."
update-rc.d docker defaults || true

# 11. Test init script
echo "11. Testing init script..."

echo "--- Starting Docker via init script ---"
if /etc/init.d/docker start; then
    echo "✓ Init script started Docker successfully!"
    
    # Give time for full initialization
    sleep 3
    
    echo "--- Checking status ---"
    /etc/init.d/docker status
    
    # Check socket
    if [ -S /var/run/docker.sock ]; then
        echo "✓ Docker socket created"
        
        # Check CLI
        echo "--- Checking Docker CLI ---"
        if docker version 2>/dev/null; then
            echo "✓ Docker CLI works"
            
            # Check docker compose
            echo "--- Checking Docker Compose ---"
            if docker compose version 2>/dev/null; then
                echo "✓ Docker Compose works"
                
                # Final test - hello-world
                echo "--- Final test: hello-world ---"
                if docker run --rm hello-world 2>/dev/null; then
                    echo ""
                    echo "======================================"
                    echo "✓✓✓ EVERYTHING WORKS PERFECTLY! ✓✓✓"
                    echo "======================================"
                else
                    echo "⚠ Container didn't start, but Docker is working"
                fi
            else
                echo "⚠ Docker Compose not working"
            fi
        else
            echo "⚠ Docker CLI not working"
        fi
    else
        echo "✗ Docker socket not created"
        echo "Check logs: cat /var/log/docker.log"
    fi
else
    echo "✗ Init script failed to start Docker"
    echo ""
    echo "=== ERROR LOGS ==="
    cat /var/log/docker.log
    echo "==================="
fi

# 12. Setup user
echo ""
echo "12. Setting up user permissions..."
groupadd docker 2>/dev/null || true
CURRENT_USER=${SUDO_USER:-$(whoami)}
if [ "$CURRENT_USER" != "root" ]; then
    usermod -aG docker "$CURRENT_USER" 2>/dev/null || true
    echo "User $CURRENT_USER added to docker group"
    echo "IMPORTANT: Log out and log back in for group permissions to take effect!"
fi

echo ""
echo "========================================"
echo "INSTALLATION COMPLETED!"
echo "========================================"
echo "Management commands:"
echo "  sudo /etc/init.d/docker start      # Start"
echo "  sudo /etc/init.d/docker stop       # Stop"
echo "  sudo /etc/init.d/docker restart    # Restart"
echo "  sudo /etc/init.d/docker status     # Status"
echo ""
echo "Verification:"
echo "  docker ps"
echo "  docker compose version"
echo "  docker run hello-world"
echo ""
echo "Diagnostics (if problems occur):"
echo "  cat /var/log/docker.log           # Docker logs"
echo "  ps aux | grep dockerd             # Docker processes"
echo "  ls -la /var/run/docker.sock       # Check socket"
echo "  docker info                       # Docker system info"
echo "========================================"

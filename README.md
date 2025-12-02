# Podman + Caddy Reverse Proxy Setup Guide

## Overview

This guide sets up a secure multi-project server using:
- **Podman** (rootless containers)
- **Caddy** (automatic HTTPS reverse proxy)
- **systemd** (service management)
- **One user per project** (security isolation)

## Architecture

```
Internet → Caddy (port 80/443) → Podman Network → Project Containers
                                                   ├─ project1 (user: proj1)
                                                   ├─ project2 (user: proj2)
                                                   └─ project3 (user: proj3)
```

## Initial Setup

### 1. Install Podman and Caddy

```bash
# Update system
sudo dnf update -y  # or apt update on Debian/Ubuntu

# Install Podman
sudo dnf install -y podman podman-plugins  # RHEL/Fedora
# sudo apt install -y podman  # Debian/Ubuntu

# Install Caddy
sudo dnf install -y 'dnf-command(copr)'
sudo dnf copr enable -y @caddy/caddy
sudo dnf install -y caddy

# Or on Debian/Ubuntu:
# sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
# curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
# curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
# sudo apt update
# sudo apt install caddy
```

### 2. Enable Lingering for Rootless Containers

This allows user containers to start at boot without the user being logged in:

```bash
# For each project user you'll create
sudo loginctl enable-linger proj1
sudo loginctl enable-linger proj2
sudo loginctl enable-linger proj3
```

### 3. Create Podman Network

Create a shared network for all projects (do this as your main user):

```bash
# Create network
podman network create --subnet 10.89.0.0/24 caddy-net

# Verify
podman network inspect caddy-net
```

## Per-Project Setup

For each project, follow these steps:

### 1. Create Project User

```bash
# Create user (no login shell for security)
sudo useradd -m -s /sbin/nologin proj1
sudo loginctl enable-linger proj1

# Set up directories
sudo mkdir -p /home/proj1/{container-data,Dockerfile}
sudo chown -R proj1:proj1 /home/proj1
```

### 2. Create Dockerfile

```bash
# Example Dockerfile for project1
sudo tee /home/proj1/Dockerfile/Dockerfile << 'EOF'
FROM nginx:alpine

# Copy your application files
COPY ./app /usr/share/nginx/html

# Nginx already exposes port 80
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
EOF

# Set ownership
sudo chown -R proj1:proj1 /home/proj1/Dockerfile
```

### 3. Build Container Image

```bash
# Build as the project user
sudo -u proj1 podman build -t proj1-image /home/proj1/Dockerfile/

# Verify
sudo -u proj1 podman images
```

### 4. Create systemd Service

```bash
# Create user systemd directory
sudo mkdir -p /home/proj1/.config/systemd/user
sudo chown -R proj1:proj1 /home/proj1/.config

# Create service file
sudo tee /home/proj1/.config/systemd/user/proj1-container.service << 'EOF'
[Unit]
Description=Project 1 Container
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
NotifyAccess=all
Restart=always
RestartSec=10s
TimeoutStartSec=120s

# Resource limits
MemoryMax=1G
CPUQuota=100%

# Security settings
NoNewPrivileges=true
PrivateTmp=true

# Run the container
ExecStartPre=-/usr/bin/podman kill proj1-container
ExecStartPre=-/usr/bin/podman rm proj1-container
ExecStart=/usr/bin/podman run \
  --name proj1-container \
  --network caddy-net \
  --ip 10.89.0.10 \
  --publish 127.0.0.1:8001:80 \
  --volume /home/proj1/container-data:/data:Z \
  --security-opt no-new-privileges=true \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  --read-only \
  --tmpfs /tmp \
  --label io.containers.autoupdate=registry \
  proj1-image

ExecStop=/usr/bin/podman stop -t 10 proj1-container
ExecStopPost=/usr/bin/podman rm -f proj1-container

[Install]
WantedBy=default.target
EOF

# Set ownership
sudo chown proj1:proj1 /home/proj1/.config/systemd/user/proj1-container.service
```

### 5. Enable and Start Service

```bash
# Reload systemd as the user
sudo -u proj1 XDG_RUNTIME_DIR=/run/user/$(id -u proj1) \
  systemctl --user daemon-reload

# Enable and start
sudo -u proj1 XDG_RUNTIME_DIR=/run/user/$(id -u proj1) \
  systemctl --user enable --now proj1-container.service

# Check status
sudo -u proj1 XDG_RUNTIME_DIR=/run/user/$(id -u proj1) \
  systemctl --user status proj1-container.service

# View logs
sudo -u proj1 XDG_RUNTIME_DIR=/run/user/$(id -u proj1) \
  journalctl --user -u proj1-container.service -f
```

## Caddy Configuration

### 1. Configure Caddyfile

```bash
sudo tee /etc/caddy/Caddyfile << 'EOF'
# Global options
{
    email your-email@example.com
    # Uncomment for staging (testing):
    # acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}

# Project 1
project1.yourdomain.com {
    reverse_proxy 127.0.0.1:8001
    
    # Security headers
    header {
        # Enable HSTS
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        # Prevent clickjacking
        X-Frame-Options "SAMEORIGIN"
        # Prevent MIME sniffing
        X-Content-Type-Options "nosniff"
        # XSS protection
        X-XSS-Protection "1; mode=block"
        # Referrer policy
        Referrer-Policy "strict-origin-when-cross-origin"
    }
    
    # Logging
    log {
        output file /var/log/caddy/project1.log
        format json
    }
}

# Project 2
project2.yourdomain.com {
    reverse_proxy 127.0.0.1:8002
    
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
        Referrer-Policy "strict-origin-when-cross-origin"
    }
    
    log {
        output file /var/log/caddy/project2.log
        format json
    }
}

# Add more projects as needed...
EOF
```

### 2. Create Log Directory

```bash
sudo mkdir -p /var/log/caddy
sudo chown caddy:caddy /var/log/caddy
```

### 3. Enable and Start Caddy

```bash
# Test configuration
sudo caddy validate --config /etc/caddy/Caddyfile

# Enable and start
sudo systemctl enable --now caddy

# Check status
sudo systemctl status caddy

# View logs
sudo journalctl -u caddy -f
```

## Security Best Practices

### 1. Firewall Configuration

```bash
# Allow only HTTP/HTTPS
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# Or with ufw:
# sudo ufw allow 80/tcp
# sudo ufw allow 443/tcp
# sudo ufw enable
```

### 2. SELinux (if enabled)

```bash
# Allow Caddy to connect to containers
sudo setsebool -P httpd_can_network_connect 1

# Set proper contexts for volumes
sudo semanage fcontext -a -t container_file_t "/home/proj1/container-data(/.*)?"
sudo restorecon -R /home/proj1/container-data
```

### 3. Container Security Hardening

The systemd service already includes:
- `--cap-drop ALL` - Removes all capabilities
- `--cap-add NET_BIND_SERVICE` - Only adds necessary capabilities
- `--security-opt no-new-privileges=true` - Prevents privilege escalation
- `--read-only` - Read-only root filesystem
- `--tmpfs /tmp` - Writable tmp in memory
- `NoNewPrivileges=true` - systemd level protection
- Resource limits (MemoryMax, CPUQuota)

### 4. Regular Updates

Create an update script:

```bash
sudo tee /usr/local/bin/update-containers.sh << 'EOF'
#!/bin/bash

# Update all project containers
for user in proj1 proj2 proj3; do
    echo "Updating $user container..."
    
    # Pull latest image (if using registry)
    sudo -u $user podman pull proj${user: -1}-image 2>/dev/null || true
    
    # Restart service
    sudo -u $user XDG_RUNTIME_DIR=/run/user/$(id -u $user) \
      systemctl --user restart ${user}-container.service
done

# Update Caddy
sudo systemctl restart caddy

echo "Updates complete!"
EOF

sudo chmod +x /usr/local/bin/update-containers.sh
```

### 5. Monitoring

```bash
# Check all container statuses
for user in proj1 proj2 proj3; do
    echo "=== $user ==="
    sudo -u $user XDG_RUNTIME_DIR=/run/user/$(id -u $user) \
      systemctl --user status ${user}-container.service --no-pager
done

# Check Caddy
sudo systemctl status caddy --no-pager

# View Caddy access logs
sudo tail -f /var/log/caddy/*.log
```

## Adding a New Project

Quick checklist:

1. Create user: `sudo useradd -m -s /sbin/nologin proj3`
2. Enable lingering: `sudo loginctl enable-linger proj3`
3. Create directories: `sudo mkdir -p /home/proj3/{container-data,Dockerfile}`
4. Add Dockerfile and build image
5. Create systemd service (use unique port and IP)
6. Enable service
7. Add domain to Caddyfile
8. Reload Caddy: `sudo systemctl reload caddy`

## Troubleshooting

### Container won't start

```bash
# Check logs
sudo -u proj1 XDG_RUNTIME_DIR=/run/user/$(id -u proj1) \
  journalctl --user -u proj1-container.service -n 50

# Test container manually
sudo -u proj1 podman run -it --rm proj1-image /bin/sh
```

### Network issues

```bash
# Check network exists
podman network ls

# Verify container is on network
sudo -u proj1 podman inspect proj1-container | grep -A 10 Networks
```

### Caddy issues

```bash
# Test configuration
sudo caddy validate --config /etc/caddy/Caddyfile

# Check logs
sudo journalctl -u caddy -n 50

# Test certificate
curl -v https://project1.yourdomain.com
```

## Alternative: Using podman-compose (Not Recommended)

If you still prefer podman-compose, here's a minimal example:

```yaml
# docker-compose.yml
version: '3'

services:
  project1:
    build: ./project1
    container_name: proj1-container
    networks:
      caddy-net:
        ipv4_address: 10.89.0.10
    ports:
      - "127.0.0.1:8001:80"
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE

networks:
  caddy-net:
    external: true
```

Run with: `podman-compose up -d`

**However**, this doesn't give you:
- Per-project user isolation
- systemd integration
- Easy resource limits
- Automatic restarts on failure
- Boot-time startup

## Summary

This setup provides:

✅ **Security**: Each project runs as a different unprivileged user  
✅ **Isolation**: Containers have minimal capabilities and read-only filesystems  
✅ **Automatic HTTPS**: Caddy handles certificates automatically  
✅ **Reliability**: systemd restarts failed containers  
✅ **Scalability**: Easy to add new projects  
✅ **Monitoring**: Integrated with journald and Caddy logging  

Your projects are now production-ready with enterprise-grade security!

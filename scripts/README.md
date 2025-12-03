# Scripts

Management scripts for the Podman + Caddy router setup.

## Configuration File

All projects are tracked in `/etc/router-projects.json` with this format:

```json
[
  {
    "slug": "proj1",
    "git": "git@github.com:user/repo.git",
    "branch": "main"
  },
  {
    "slug": "myapp",
    "git": "git@github.com:user/myapp.git",
    "branch": "prod"
  }
]
```

This config file:
- Is automatically updated when you add new projects
- Can be copied to recreate your entire setup on another machine
- Is used to generate the Caddyfile

**Note:** Requires `jq` to be installed: `sudo apt install jq`

---

## bootstrap.sh

Recreates all projects from `router-projects.json` (useful for new machines).

```bash
sudo ./scripts/bootstrap.sh
```

**What it does:**
1. Reads all projects from `/etc/router-projects.json`
2. For each project that doesn't exist, runs `new.sh`
3. Reports success/skip/fail counts

**Use this when:**
- Setting up a new server with an existing config
- Migrating your setup to another machine
- Recovering from a system reinstall

---

## generate-caddyfile.sh

Generates a complete Caddyfile from `router-projects.json`.

```bash
sudo ./scripts/generate-caddyfile.sh [domain] [email]
```

**Example:**
```bash
# Generate and save to file
sudo ./scripts/generate-caddyfile.sh yourdomain.com admin@yourdomain.com > /etc/caddy/Caddyfile

# Or just preview
sudo ./scripts/generate-caddyfile.sh yourdomain.com admin@yourdomain.com
```

**What it does:**
1. Reads projects from `/etc/router-projects.json`
2. Generates Caddyfile with reverse proxy config for each project
3. Includes security headers and logging
4. Skips projects where the user doesn't exist

**Parameters:**
- `domain` - Your domain (default: yourdomain.com)
- `email` - Email for Let's Encrypt (default: your-email@example.com)

---

## new.sh

Creates a new project with user, container, and systemd service.

```bash
sudo ./scripts/new.sh <project_slug> <git_uri> <branch>
```

**Example:**
```bash
sudo ./scripts/new.sh proj1 git@github.com:user/repo.git prod
```

**What it does:**
1. Creates system user with the project slug
2. Generates SSH deploy key (you'll need to add it to your git repo)
3. Clones the git repository
4. Builds the container image
5. Creates and starts systemd service
6. Adds project to `/etc/router-projects.json`
7. Shows next steps to generate Caddyfile

**Note:** Port and IP are auto-calculated from the user ID.

---

## update.sh

Updates a project by pulling latest code and rebuilding.

```bash
sudo ./scripts/update.sh <project_slug>
```

**Example:**
```bash
sudo ./scripts/update.sh proj1
```

**What it does:**
1. Pulls latest changes from git
2. If changes detected:
   - Backs up current image as `:old`
   - Builds new image
   - Restarts the service
3. If no changes, exits without rebuilding

**Note:** Keeps previous image for rollback.

---

## rollback.sh

Rolls back a project to the previous image.

```bash
sudo ./scripts/rollback.sh <project_slug>
```

**Example:**
```bash
sudo ./scripts/rollback.sh proj1
```

**What it does:**
1. Requires confirmation (type "yes")
2. Stops the service
3. Tags current image as `:broken`
4. Restores previous (`:old`) image
5. Restarts the service

**Note:** Only works if you've previously run `update.sh`.

---

## restart.sh

Simply restarts a project container.

```bash
sudo ./scripts/restart.sh <project_slug>
```

**Example:**
```bash
sudo ./scripts/restart.sh proj1
```

**What it does:**
1. Restarts the systemd service
2. Shows service status

**Use this when:**
- You've updated the `.env` file
- You need to restart without rebuilding
- You're troubleshooting issues

---

## Workflow Example

### Initial Setup
```bash
# Install jq (required for config management)
sudo apt install jq

# Create new project
sudo ./scripts/new.sh myapp git@github.com:me/myapp.git main

# Generate and deploy Caddyfile
sudo ./scripts/generate-caddyfile.sh yourdomain.com admin@yourdomain.com > /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

### Setting Up on a New Machine
```bash
# Copy your config file to the new machine
scp /etc/router-projects.json newserver:/tmp/

# On the new server:
sudo mv /tmp/router-projects.json /etc/
sudo ./scripts/bootstrap.sh

# Generate Caddyfile
sudo ./scripts/generate-caddyfile.sh yourdomain.com admin@yourdomain.com > /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

### Regular Updates
```bash
# Update to latest code
sudo ./scripts/update.sh myapp
```

### If Something Goes Wrong
```bash
# Rollback to previous version
sudo ./scripts/rollback.sh myapp
```

### Configuration Changes
```bash
# Edit environment variables
sudo nano /home/myapp/.env

# Restart to apply changes
sudo ./scripts/restart.sh myapp
```

---

## Directory Structure

After running `new.sh`, each project has:

```
/home/<project_slug>/
├── .env                 # Environment variables (empty by default)
├── .ssh/                # SSH keys for git access
│   └── id_ed25519      # Deploy key
├── app/                 # Cloned git repository
│   └── Dockerfile      # Must be in repo root
├── container-data/      # Persistent volume mounted to /data
└── .config/systemd/user/
    └── <slug>-container.service
```

---

## Notes

- All scripts require `sudo`
- Port is auto-assigned: `8000 + user_id`
- IP is auto-assigned: `10.67.0.(10 + (user_id % 246))`
- Containers listen on port 80 internally
- Empty `.env` file is created for extensibility

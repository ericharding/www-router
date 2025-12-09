# Scripts

Management scripts for the Podman + Caddy router setup.

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
6. Outputs Caddyfile configuration to add

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
# Create new project
sudo ./scripts/new.sh myapp git@github.com:me/myapp.git main

# Add the Caddyfile configuration (output by script)
sudo nano /etc/caddy/Caddyfile
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

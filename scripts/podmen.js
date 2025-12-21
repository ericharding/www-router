#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const os = require('os');

// Parse command-line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  const config = {
    configPath: path.join(os.homedir(), '.config', 'podmen.conf'),
    command: null,
    params: []
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === '--config' || arg === '-c') {
      config.configPath = args[++i];
    } else if (!config.command) {
      config.command = arg;
    } else {
      config.params.push(arg);
    }
  }

  return config;
}

// Load configuration file
function loadConfig(configPath) {
  try {
    const content = fs.readFileSync(configPath, 'utf8');
    return JSON.parse(content);
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.error(`Config file not found: ${configPath}`);
      process.exit(1);
    }
    throw err;
  }
}

// Get all users from config
function getUsers(config) {
  const users = [];

  // Handle users map (object keyed by username)
  if (config.users && typeof config.users === 'object' && !Array.isArray(config.users)) {
    for (const [username, userData] of Object.entries(config.users)) {
      users.push({
        name: username,
        ...userData
      });
    }
  }

  return users;
}

// Add a new user without login privileges and enable linger
function addUser(username) {
  try {
    console.log(`Adding user: ${username}`);

    // Add user without login privileges (using /usr/sbin/nologin)
    execSync(`sudo useradd -r -s /usr/sbin/nologin ${username}`, { stdio: 'inherit' });

    console.log(`Enabling linger for user: ${username}`);

    // Enable linger for persistent systemd services
    execSync(`sudo loginctl enable-linger ${username}`, { stdio: 'inherit' });

    console.log(`User ${username} added successfully`);
  } catch (err) {
    console.error(`Failed to add user ${username}:`, err.message);
    process.exit(1);
  }
}

// Run podman ps for all users
function podmanPs(configPath) {
  const config = loadConfig(configPath);
  const users = getUsers(config);

  if (users.length === 0) {
    console.log('No users found in config');
    return;
  }

  users.forEach(user => {
    const username = user.name;
    console.log(`\n=== Containers for user: ${username} ===`);

    try {
      execSync(`sudo -u ${username} podman ps`, { stdio: 'inherit' });
    } catch (err) {
      console.error(`Failed to run podman ps for user ${username}:`, err.message);
    }
  });
}

// Show usage information
function showUsage() {
  console.log(`Usage: podmen [options] <command> [arguments]

Commands:
  adduser <name>    Add a new user without login privileges and enable linger
  ps                Show podman containers for all configured users

Options:
  -c, --config <path>    Specify config file path (default: ~/.config/podmen.conf)

Examples:
  podmen adduser web
  podmen ps
  podmen --config /etc/podmen.conf ps
`);
}

// Main entry point
function main() {
  const config = parseArgs();

  if (!config.command) {
    showUsage();
    process.exit(1);
  }

  switch (config.command) {
    case 'adduser':
      if (config.params.length === 0) {
        console.error('Error: username required for adduser command');
        showUsage();
        process.exit(1);
      }
      addUser(config.params[0]);
      break;

    case 'ps':
      podmanPs(config.configPath);
      break;

    default:
      console.error(`Unknown command: ${config.command}`);
      showUsage();
      process.exit(1);
  }
}

main();

#!/usr/bin/env rust-script

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, exit};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
struct User {
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    uid: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    env: Option<std::collections::HashMap<String, String>>,
}

#[derive(Debug, Deserialize)]
struct Config {
    #[serde(skip_serializing_if = "Option::is_none")]
    user: Option<User>,
    #[serde(skip_serializing_if = "Option::is_none")]
    users: Option<Vec<User>>,
}

struct Args {
    config_path: PathBuf,
    command: Option<String>,
    params: Vec<String>,
}

fn parse_args() -> Args {
    let args: Vec<String> = env::args().skip(1).collect();
    let home = env::var("HOME").unwrap_or_else(|_| "/root".to_string());
    let mut config_path = PathBuf::from(&home).join(".config").join("podmen.conf");
    let mut command = None;
    let mut params = Vec::new();

    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];

        if arg == "--config" || arg == "-c" {
            i += 1;
            if i < args.len() {
                config_path = PathBuf::from(&args[i]);
            } else {
                eprintln!("Error: --config requires a path argument");
                exit(1);
            }
        } else if command.is_none() {
            command = Some(arg.clone());
        } else {
            params.push(arg.clone());
        }

        i += 1;
    }

    Args {
        config_path,
        command,
        params,
    }
}

fn load_config(config_path: &PathBuf) -> Config {
    let content = fs::read_to_string(config_path).unwrap_or_else(|err| {
        eprintln!("Config file not found: {}", config_path.display());
        eprintln!("Error: {}", err);
        exit(1);
    });

    serde_json::from_str(&content).unwrap_or_else(|err| {
        eprintln!("Failed to parse config file: {}", err);
        exit(1);
    })
}

fn get_users(config: &Config) -> Vec<&User> {
    let mut users = Vec::new();

    if let Some(ref user) = config.user {
        users.push(user);
    }

    if let Some(ref user_list) = config.users {
        users.extend(user_list.iter());
    }

    users
}

fn add_user(username: &str) {
    println!("Adding user: {}", username);

    // Add user without login privileges
    let status = Command::new("sudo")
        .arg("useradd")
        .arg("-r")
        .arg("-s")
        .arg("/usr/sbin/nologin")
        .arg(username)
        .status()
        .unwrap_or_else(|err| {
            eprintln!("Failed to execute useradd: {}", err);
            exit(1);
        });

    if !status.success() {
        eprintln!("Failed to add user {}", username);
        exit(1);
    }

    println!("Enabling linger for user: {}", username);

    // Enable linger for persistent systemd services
    let status = Command::new("sudo")
        .arg("loginctl")
        .arg("enable-linger")
        .arg(username)
        .status()
        .unwrap_or_else(|err| {
            eprintln!("Failed to execute loginctl: {}", err);
            exit(1);
        });

    if !status.success() {
        eprintln!("Failed to enable linger for user {}", username);
        exit(1);
    }

    println!("User {} added successfully", username);
}

fn podman_ps(config_path: &PathBuf) {
    let config = load_config(config_path);
    let users = get_users(&config);

    if users.is_empty() {
        println!("No users found in config");
        return;
    }

    for user in users {
        println!("\n=== Containers for user: {} ===", user.name);

        let status = Command::new("sudo")
            .arg("-u")
            .arg(&user.name)
            .arg("podman")
            .arg("ps")
            .status();

        match status {
            Ok(s) if !s.success() => {
                eprintln!("podman ps failed for user {}", user.name);
            }
            Err(err) => {
                eprintln!("Failed to run podman ps for user {}: {}", user.name, err);
            }
            _ => {}
        }
    }
}

fn show_usage() {
    println!("Usage: podmen [options] <command> [arguments]

Commands:
  adduser <name>    Add a new user without login privileges and enable linger
  ps                Show podman containers for all configured users

Options:
  -c, --config <path>    Specify config file path (default: ~/.config/podmen.conf)

Examples:
  podmen adduser web
  podmen ps
  podmen --config /etc/podmen.conf ps
");
}

fn main() {
    let args = parse_args();

    match args.command.as_deref() {
        Some("adduser") => {
            if args.params.is_empty() {
                eprintln!("Error: username required for adduser command");
                show_usage();
                exit(1);
            }
            add_user(&args.params[0]);
        }
        Some("ps") => {
            podman_ps(&args.config_path);
        }
        Some(cmd) => {
            eprintln!("Unknown command: {}", cmd);
            show_usage();
            exit(1);
        }
        None => {
            show_usage();
            exit(1);
        }
    }
}

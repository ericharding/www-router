#!/usr/bin/env rust-script

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, exit};
use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize)]
struct UserData {
    #[serde(skip_serializing_if = "Option::is_none")]
    uid: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    env: Option<HashMap<String, String>>,
}

#[derive(Debug, Deserialize)]
struct Config {
    #[serde(skip_serializing_if = "Option::is_none")]
    users: Option<HashMap<String, UserData>>,
}

#[derive(Parser)]
#[command(name = "podmen")]
#[command(about = "Manage podman users and containers", long_about = None)]
struct Cli {
    /// Specify config file path
    #[arg(short, long, value_name = "PATH", default_value = None)]
    config: Option<PathBuf>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Add a new user without login privileges and enable linger
    Adduser {
        /// Username to add
        name: String,
    },
    /// Show podman containers for all configured users
    Ps,
}

fn get_config_path(config_arg: Option<PathBuf>) -> PathBuf {
    config_arg.unwrap_or_else(|| {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/root".to_string());
        PathBuf::from(&home).join(".config").join("podmen.conf")
    })
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

fn get_users(config: &Config) -> Vec<(&String, &UserData)> {
    let mut users = Vec::new();

    if let Some(ref user_map) = config.users {
        users.extend(user_map.iter());
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

    for (username, _user_data) in users {
        println!("\n=== Containers for user: {} ===", username);

        let status = Command::new("sudo")
            .arg("-u")
            .arg(username)
            .arg("podman")
            .arg("ps")
            .status();

        match status {
            Ok(s) if !s.success() => {
                eprintln!("podman ps failed for user {}", username);
            }
            Err(err) => {
                eprintln!("Failed to run podman ps for user {}: {}", username, err);
            }
            _ => {}
        }
    }
}

fn main() {
    let cli = Cli::parse();
    let config_path = get_config_path(cli.config);

    match cli.command {
        Commands::Adduser { name } => {
            add_user(&name);
        }
        Commands::Ps => {
            podman_ps(&config_path);
        }
    }
}

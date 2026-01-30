use std::fs;
use std::path::{Path, PathBuf};

use crate::protocol::AppInfo;

pub struct AppManager {}

impl AppManager {
    pub fn get_installed_apps() -> Vec<AppInfo> {
        let mut apps = Vec::new();
        let paths = vec![
            PathBuf::from("/usr/share/applications"),
            dirs::home_dir().unwrap().join(".local/share/applications"),
        ];

        for path in paths {
            if let Ok(entries) = fs::read_dir(path) {
                for entry in entries {
                    if let Ok(entry) = entry {
                        let path = entry.path();
                        if path.extension().map_or(false, |ext| ext == "desktop") {
                            if let Some(mut app) = Self::parse_desktop_file(&path) {
                                // Try to get icon base64
                                if !app.icon.is_empty() {
                                    app.icon_base64 = Self::get_icon_base64(&app.icon);
                                }
                                
                                // Basic deduplication by name
                                if !apps.iter().any(|a: &AppInfo| a.name == app.name) {
                                    apps.push(app);
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Sort alphabetically
        apps.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
        apps.truncate(60); // Slightly more apps
        apps
    }

    fn get_icon_base64(icon_name: &str) -> Option<String> {
        if icon_name.is_empty() { return None; }

        // 1. If absolute path, use it directly
        let icon_path = if icon_name.starts_with('/') {
            PathBuf::from(icon_name)
        } else {
            // 2. Search common paths
            let search_paths = vec![
                format!("/usr/share/icons/hicolor/scalable/apps/{}.svg", icon_name),
                format!("/usr/share/icons/hicolor/48x48/apps/{}.png", icon_name),
                format!("/usr/share/icons/hicolor/128x128/apps/{}.png", icon_name),
                format!("/usr/share/icons/hicolor/256x256/apps/{}.png", icon_name),
                format!("/usr/share/icons/hicolor/512x512/apps/{}.png", icon_name),
                format!("/usr/share/pixmaps/{}.png", icon_name),
                format!("/usr/share/pixmaps/{}.xpm", icon_name),
                format!("/usr/share/pixmaps/{}.svg", icon_name),
                format!("{}/.local/share/icons/{}.png", dirs::home_dir()?.to_str()?, icon_name),
                format!("{}/.local/share/icons/{}.svg", dirs::home_dir()?.to_str()?, icon_name),
            ];

            let mut found = None;
            for p in search_paths {
                let path = PathBuf::from(p);
                if path.exists() {
                    found = Some(path);
                    break;
                }
            }
            
            // Fallback for some themes where icon name is just a name and we need to find it in active theme
            if found.is_none() {
                let theme_paths = vec!["/usr/share/icons/Adwaita", "/usr/share/icons/breeze", "/usr/share/icons/Papirus"];
                for tp in theme_paths {
                    let cmd = std::process::Command::new("find")
                        .arg(tp)
                        .arg("-name")
                        .arg(format!("{}.*", icon_name))
                        .output();
                    if let Ok(out) = cmd {
                        let res = String::from_utf8_lossy(&out.stdout);
                        if let Some(first_path) = res.lines().next() {
                            found = Some(PathBuf::from(first_path));
                            break;
                        }
                    }
                }
            }

            found?
        };

        if !icon_path.exists() { return None; }

        // Read file and encode to base64
        let data = fs::read(&icon_path).ok()?;
        use base64::Engine;
        Some(base64::engine::general_purpose::STANDARD.encode(data))
    }

    fn parse_desktop_file(path: &Path) -> Option<AppInfo> {
        let content = fs::read_to_string(path).ok()?;
        let mut name = None;
        let mut exec = None;
        let mut icon = None;
        let mut no_display = false;

        for line in content.lines() {
            let line = line.trim();
            if line.starts_with("Name=") && name.is_none() { 
                name = Some(line[5..].to_string()); 
            }
            else if line.starts_with("Exec=") && exec.is_none() { 
                // Just take the command, ignore args like %u %f
                exec = Some(line[5..].split_whitespace().next()?.to_string()); 
            }
            else if line.starts_with("Icon=") && icon.is_none() { 
                icon = Some(line[5..].to_string()); 
            }
            else if line.starts_with("NoDisplay=true") { 
                no_display = true; 
            }
        }

        if no_display { return None; }

        if let (Some(n), Some(e)) = (name, exec) {
            Some(AppInfo {
                name: n,
                exec: e,
                icon: icon.unwrap_or_default(),
                icon_base64: None,
            })
        } else {
            None
        }
    }
}

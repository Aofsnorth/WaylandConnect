use zbus::{Connection, Proxy};
use std::collections::HashMap;
use crate::protocol::MediaMetadata;
use log::{error, info, debug};

pub struct MediaManager {
}

impl MediaManager {
    pub fn new() -> Self {
        Self {}
    }

    async fn get_player_names(conn: &Connection) -> anyhow::Result<Vec<String>> {
        let dbus_proxy = Proxy::new(
            conn,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
        ).await?;

        let names: Vec<String> = dbus_proxy.call("ListNames", &()).await?;
        Ok(names.into_iter()
            .filter(|name| name.starts_with("org.mpris.MediaPlayer2."))
            .collect())
    }

    async fn find_best_player(&self, conn: &Connection) -> Option<String> {
        let player_names = Self::get_player_names(conn).await.ok()?;
        if player_names.is_empty() { 
            debug!("No MPRIS players found on D-Bus");
            return None; 
        }

        let mut playing = Vec::new();
        let mut paused = Vec::new();
        let mut other = Vec::new();

        for name in player_names {
            if let Ok(proxy) = Proxy::new(conn, name.as_str(), "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player").await {
                // Get status with a default if it fails
                let status: String = proxy.get_property("PlaybackStatus").await.unwrap_or_else(|_| "Unknown".to_string());
                
                let low_name = name.to_lowercase();
                let is_browser = low_name.contains("chromium") 
                                || low_name.contains("firefox")
                                || low_name.contains("chrome")
                                || low_name.contains("browser")
                                || low_name.contains("brave");
                
                match status.as_str() {
                    "Playing" => {
                        if !is_browser { playing.insert(0, name); } // Prioritize music apps
                        else { playing.push(name); }
                    },
                    "Paused" => {
                        if !is_browser { paused.insert(0, name); }
                        else { paused.push(name); }
                    },
                    _ => {
                        other.push(name);
                    }
                }
            }
        }

        playing.into_iter().next()
            .or_else(|| paused.into_iter().next())
            .or_else(|| other.into_iter().next())
    }

    pub async fn get_current_player_metadata(&self) -> Option<MediaMetadata> {
        let conn = match Connection::session().await {
            Ok(c) => c,
            Err(e) => {
                error!("Failed to connect to D-Bus session bus: {}", e);
                return None;
            }
        };
        
        let best_player = self.find_best_player(&conn).await?;
        debug!("Selected media player: {}", best_player);
        self.get_player_info(&conn, &best_player).await.ok()
    }

    async fn get_player_info(&self, conn: &Connection, dest: &str) -> anyhow::Result<MediaMetadata> {
        let proxy = Proxy::new(
            conn,
            dest,
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
        ).await?;

        let metadata: HashMap<String, zbus::zvariant::Value> = proxy.get_property("Metadata").await.unwrap_or_default();
        let status: String = proxy.get_property("PlaybackStatus").await.unwrap_or_else(|_| "Stopped".to_string());
        let position: i64 = proxy.get_property("Position").await.unwrap_or(0);
        let volume: f64 = proxy.get_property("Volume").await.unwrap_or(1.0);
        let shuffle: bool = proxy.get_property("Shuffle").await.unwrap_or(false);
        let loop_status: String = proxy.get_property("LoopStatus").await.unwrap_or_else(|_| "None".to_string());

        // Extract track_id
        let track_id = if let Some(zbus::zvariant::Value::Str(id)) = metadata.get("mpris:trackid") {
            id.to_string()
        } else if let Some(zbus::zvariant::Value::ObjectPath(path)) = metadata.get("mpris:trackid") {
            path.to_string()
        } else {
            "/org/mpris/MediaPlayer2/TrackList/NoTrack".to_string()
        };

        // Extract Title with multiple fallbacks
        let title = metadata.get("xesam:title")
            .and_then(|v| {
                if let zbus::zvariant::Value::Str(s) = v { Some(s.to_string()) } else { None }
            })
            .or_else(|| {
                // Fallback for some browsers or players that use different keys or just file name
                metadata.get("mpris:trackid").map(|v| v.to_string().split('/').last().unwrap_or("Unknown").to_string())
            })
            .unwrap_or_else(|| "Active Session".to_string());

        // Extract Artist
        let artist = if let Some(zbus::zvariant::Value::Array(arr)) = metadata.get("xesam:artist") {
             let artists: Vec<String> = arr.get().iter().filter_map(|v| {
                 if let zbus::zvariant::Value::Str(s) = v { Some(s.to_string()) } else { None }
             }).collect();
             if artists.is_empty() { "Various Artists".to_string() } else { artists.join(", ") }
        } else if let Some(zbus::zvariant::Value::Str(s)) = metadata.get("xesam:artist") {
            s.to_string()
        } else {
            "Unknown Source".to_string()
        };

        let album = if let Some(zbus::zvariant::Value::Str(s)) = metadata.get("xesam:album") {
            s.to_string()
        } else {
            "".to_string()
        };

        let art_url = if let Some(zbus::zvariant::Value::Str(s)) = metadata.get("mpris:artUrl") {
            s.to_string()
        } else if let Some(zbus::zvariant::Value::Str(s)) = metadata.get("xesam:url") {
            // Some players use the file url as art source or just metadata
            s.to_string()
        } else {
            "".to_string()
        };

        let mut duration = if let Some(val) = metadata.get("mpris:length") {
            match val {
                zbus::zvariant::Value::I64(d) => *d,
                zbus::zvariant::Value::U64(d) => *d as i64,
                _ => 0,
            }
        } else if let Some(zbus::zvariant::Value::I64(d)) = metadata.get("xesam:duration") {
            *d
        } else {
            0
        };

        if duration == 0 {
            // Final fallback: check the property directly if not in metadata hashmap
            duration = proxy.get_property("Length").await.unwrap_or(0);
        }

        Ok(MediaMetadata {
            title,
            artist,
            album,
            art_url,
            duration,
            position,
            status,
            player_name: {
                let name = dest.replace("org.mpris.MediaPlayer2.", "");
                let parts: Vec<&str> = name.split('.').collect();
                let clean_name = parts.iter()
                    .find(|&&p| !p.starts_with("instance") && p.parse::<u32>().is_err() && p != "mpris")
                    .unwrap_or(&parts[0]);
                clean_name.to_uppercase()
            },
            shuffle,
            repeat: loop_status,
            volume,
            track_id,
        })
    }

    pub async fn send_command(&self, command: &str) -> anyhow::Result<()> {
        let conn = Connection::session().await?;
        let target_player = match self.find_best_player(&conn).await {
            Some(p) => p,
            None => {
                info!("No active media player to send command '{}' to", command);
                return Ok(());
            },
        };

        let proxy = Proxy::new(
            &conn,
            target_player.as_str(),
            "/org/mpris/MediaPlayer2",
            "org.mpris.MediaPlayer2.Player",
        ).await?;

        match command {
            "play" => { let _: () = proxy.call("Play", &()).await?; },
            "pause" => { let _: () = proxy.call("Pause", &()).await?; },
            "play_pause" => { 
                let status: String = proxy.get_property("PlaybackStatus").await.unwrap_or_default();
                if status == "Paused" || status == "Stopped" {
                    let _: () = proxy.call("Play", &()).await?;
                } else {
                    let _: () = proxy.call("PlayPause", &()).await?;
                }
            },
            "next" => { let _: () = proxy.call("Next", &()).await?; },
            "previous" => { let _: () = proxy.call("Previous", &()).await?; },
            "toggle_shuffle" => {
                let current: bool = proxy.get_property("Shuffle").await.unwrap_or(false);
                let _ = proxy.set_property("Shuffle", !current).await;
            },
            "toggle_loop" => {
                let current: String = proxy.get_property("LoopStatus").await.unwrap_or_else(|_| "None".to_string());
                let next = match current.as_str() {
                    "None" => "Track",
                    "Track" => "Playlist",
                    _ => "None",
                };
                let _ = proxy.set_property("LoopStatus", next).await;
            },
            _ if command.starts_with("volume:") => {
                if let Ok(vol) = command.replace("volume:", "").parse::<f64>() {
                    let _ = proxy.set_property("Volume", vol).await;
                }
            },
            _ if command.starts_with("seek:") => {
                if let Ok(pos_usec) = command.replace("seek:", "").parse::<i64>() {
                    // SetPosition requires (TrackId, Position)
                    let metadata: HashMap<String, zbus::zvariant::Value> = proxy.get_property("Metadata").await.unwrap_or_default();
                    
                    let track_id = if let Some(zbus::zvariant::Value::Str(id)) = metadata.get("mpris:trackid") {
                        id.to_string()
                    } else if let Some(zbus::zvariant::Value::ObjectPath(path)) = metadata.get("mpris:trackid") {
                        path.to_string()
                    } else {
                        "/org/mpris/MediaPlayer2/TrackList/NoTrack".to_string()
                    };
                    
                    debug!("Seeking to {} usec on track {}", pos_usec, track_id);

                    // We need to pass the object path strictly
                    if let Ok(track_id_path) = zbus::zvariant::ObjectPath::try_from(track_id) {
                         let _: () = proxy.call("SetPosition", &(track_id_path, pos_usec)).await?;
                    }
                }
            }
            _ => {}
        }
        
        Ok(())
    }
}

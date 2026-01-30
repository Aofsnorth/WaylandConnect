use anyhow::Result;
use tokio::net::{TcpListener, TcpStream};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{mpsc, broadcast};
use tracing::{info, error};
use crate::protocol::Packet;
use std::net::SocketAddr;

pub struct TcpServer {
    bind_addr: SocketAddr,
    event_tx: mpsc::Sender<Packet>,
    broadcast_tx: broadcast::Sender<Packet>,
}

impl TcpServer {
    pub fn new(bind_addr: SocketAddr, event_tx: mpsc::Sender<Packet>, broadcast_tx: broadcast::Sender<Packet>) -> Self {
        Self { bind_addr, event_tx, broadcast_tx }
    }

    pub async fn run(&self) -> Result<()> {
        let listener = TcpListener::bind(self.bind_addr).await?;
        info!("🚀 TCP Server listening on {}", self.bind_addr);

        loop {
            let (socket, addr) = listener.accept().await?;
            info!("📡 TCP Connection from {}", addr);
            
            let event_tx = self.event_tx.clone();
            let broadcast_rx = self.broadcast_tx.subscribe();
            
            tokio::spawn(async move {
                if let Err(e) = handle_socket(socket, event_tx, broadcast_rx).await {
                    error!("TCP Error {}: {}", addr, e);
                }
            });
        }
    }
}

async fn handle_socket(
    mut socket: TcpStream, 
    event_tx: mpsc::Sender<Packet>, 
    mut broadcast_rx: broadcast::Receiver<Packet>
) -> Result<()> {
    let mut len_buf = [0u8; 4];
    
    loop {
        tokio::select! {
            // Read from Client
            read_res = socket.read_exact(&mut len_buf) => {
                read_res?;
                let len = u32::from_le_bytes(len_buf) as usize;
                let mut buf = vec![0u8; len];
                socket.read_exact(&mut buf).await?;
                
                let packet: Packet = rmp_serde::from_slice(&buf)?;
                if let Err(e) = event_tx.send(packet).await {
                    error!("Failed to forward packet: {}", e);
                    break;
                }
            }
            // Write to Client (Broadcast from Daemon)
            broadcast_res = broadcast_rx.recv() => {
                let packet = broadcast_res?;
                let payload = rmp_serde::to_vec(&packet)?;
                let len = payload.len() as u32;
                
                socket.write_all(&len.to_le_bytes()).await?;
                socket.write_all(&payload).await?;
            }
        }
    }
    
    info!("🔌 TCP Client Disconnected");
    Ok(())
}

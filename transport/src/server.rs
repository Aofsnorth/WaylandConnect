use anyhow::Result;
use quinn::{Endpoint, ServerConfig};
use tracing::{info, error};

pub struct TransportServer {
    endpoint: Endpoint,
}

impl TransportServer {
    pub async fn new(bind_addr: std::net::SocketAddr) -> Result<Self> {
        let endpoint = make_server_endpoint(bind_addr)?;
        Ok(Self { endpoint })
    }

    pub async fn run(&self) -> Result<()> {
        info!("🚀 Transport Server listening on {}", self.endpoint.local_addr()?);

        while let Some(incoming) = self.endpoint.accept().await {
            info!("📡 Incoming handshake...");
            tokio::spawn(async move {
                if let Err(e) = handle_connection(incoming).await {
                    error!("Connection error: {}", e);
                }
            });
        }

        Ok(())
    }
}

async fn handle_connection(connecting: quinn::Connecting) -> Result<()> {
    // quinn 0.10: Connecting is a Future that yields Result<Connection>
    let connection = connecting.await?;
    info!("✅ Connected: {}", connection.remote_address());
    
    // Placeholder: accept a stream
    // while let Ok((_send, _recv)) = connection.accept_bi().await {
    // }

    Ok(())
}

fn make_server_endpoint(bind_addr: std::net::SocketAddr) -> Result<Endpoint> {
    let (cert, key) = simple_cert()?;
    let server_config = ServerConfig::with_single_cert(vec![cert], key)?;
    let endpoint = Endpoint::server(server_config, bind_addr)?;
    Ok(endpoint)
}

fn simple_cert() -> Result<(rustls::Certificate, rustls::PrivateKey)> {
    let cert = rcgen::generate_simple_self_signed(vec!["localhost".into()])?;
    let key = rustls::PrivateKey(cert.serialize_private_key_der());
    let cert = rustls::Certificate(cert.serialize_der()?);
    Ok((cert, key))
}

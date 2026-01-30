use rcgen::{Certificate, CertificateParams, DistinguishedName, DnType, IsCa, SanType};
use std::fs;
use std::path::PathBuf;
use tokio_rustls::rustls::{Certificate as RustlsCert, PrivateKey as RustlsKey, ServerConfig};
use std::sync::Arc;
use log::info;
use sha2::{Sha256, Digest};

pub fn load_tls_config() -> anyhow::Result<(Arc<ServerConfig>, String)> {
    let config_dir = dirs::config_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(wc_core::constants::CONFIG_DIR_NAME);
    
    if !config_dir.exists() {
        fs::create_dir_all(&config_dir)?;
    }

    let cert_path = config_dir.join("cert.pem");
    let key_path = config_dir.join("key.pem");

    let (cert_chain, key) = if cert_path.exists() && key_path.exists() {
        info!("📜 Loading existing TLS certificates from {:?}", config_dir);
        let cert_data = fs::read(&cert_path)?;
        let key_data = fs::read(&key_path)?;
        
        let mut cert_reader = std::io::BufReader::new(&cert_data[..]);
        let certs = rustls_pemfile::certs(&mut cert_reader)?
            .into_iter()
            .map(RustlsCert)
            .collect::<Vec<_>>();
            
        let mut key_reader = std::io::BufReader::new(&key_data[..]);
        let mut keys = rustls_pemfile::pkcs8_private_keys(&mut key_reader)?;
        if keys.is_empty() {
            // Try RSA keys if PKCS8 is empty
            key_reader = std::io::BufReader::new(&key_data[..]);
            keys = rustls_pemfile::rsa_private_keys(&mut key_reader)?;
        }
        
        if keys.is_empty() {
             anyhow::bail!("No private key found in key.pem");
        }
        
        (certs, RustlsKey(keys[0].clone()))
    } else {
        info!("✨ Generating new self-signed TLS certificates...");
        let mut params = CertificateParams::default();
        params.not_before = rcgen::date_time_ymd(2023, 1, 1);
        params.not_after = rcgen::date_time_ymd(2033, 1, 1);
        params.distinguished_name = DistinguishedName::new();
        params.distinguished_name.push(DnType::CommonName, "WaylandConnect Backend");
        params.subject_alt_names = vec![SanType::DnsName("localhost".to_string())];
        params.is_ca = IsCa::NoCa;

        let cert = Certificate::from_params(params)?;
        let cert_pem = cert.serialize_pem()?;
        let key_pem = cert.serialize_private_key_pem();

        fs::write(&cert_path, &cert_pem)?;
        fs::write(&key_path, &key_pem)?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&key_path)?.permissions();
            perms.set_mode(0o600); // Read/Write only for owner
            fs::set_permissions(&key_path, perms)?;
            info!("🔒 Set strict permissions (600) on private key");
        }
        
        let mut cert_reader = std::io::BufReader::new(cert_pem.as_bytes());
        let certs = rustls_pemfile::certs(&mut cert_reader)?
            .into_iter()
            .map(RustlsCert)
            .collect::<Vec<_>>();
            
        let mut key_reader = std::io::BufReader::new(key_pem.as_bytes());
        let keys = rustls_pemfile::pkcs8_private_keys(&mut key_reader)?;
        
        (certs, RustlsKey(keys[0].clone()))
    };

    let fingerprint = {
        let mut hasher = Sha256::new();
        hasher.update(&cert_chain[0].0);
        let result = hasher.finalize();
        result.iter().map(|b| format!("{:02X}", b)).collect::<Vec<_>>().join(":")
    };

    let config = ServerConfig::builder()
        .with_safe_defaults()
        .with_no_client_auth()
        .with_single_cert(cert_chain, key)
        .map_err(|e| anyhow::anyhow!("TLS config error: {}", e))?;

    Ok((Arc::new(config), fingerprint))
}

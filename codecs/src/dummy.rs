use async_trait::async_trait;
use wc_core::traits::VideoEncoder;
use bytes::Bytes;
use wc_core::error::Result;

pub struct DummyEncoder;

#[async_trait]
impl VideoEncoder for DummyEncoder {
    fn encode(&mut self, frame: &[u8]) -> Result<Bytes> {
        // Mock compression
        Ok(Bytes::copy_from_slice(frame))
    }
    
    fn reconfigure(&mut self, _bitrate: u32, _fps: u32) -> Result<()> {
        Ok(())
    }
}

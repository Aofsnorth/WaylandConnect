use async_trait::async_trait;
use crate::error::Result;
use crate::types::FrameInfo;
use bytes::Bytes;

#[async_trait]
pub trait ScreenCapturer: Send + Sync {
    async fn start(&mut self) -> Result<FrameInfo>;
    async fn next_frame(&mut self) -> Result<Bytes>;
}

pub trait VideoEncoder: Send + Sync {
    fn encode(&mut self, frame: &[u8]) -> Result<Bytes>;
    fn reconfigure(&mut self, bitrate: u32, fps: u32) -> Result<()>;
}

#[async_trait]
pub trait TransportPeer: Send + Sync {
    async fn send(&mut self, channel_id: u8, data: &[u8]) -> Result<()>;
    async fn receive(&mut self) -> Result<(u8, Bytes)>;
}

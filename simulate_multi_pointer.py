import socket
import time
import math

# IP and Port of the overlay
UDP_IP = "127.0.0.1"
UDP_PORT = 1337

def send_msg(msg):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.sendto(msg.encode(), (UDP_IP, UDP_PORT))

def main():
    print("Starting Multi-Pointer Simulation...")
    
    # Initialize two pointers
    send_msg("device_1|START")
    send_msg("device_2|START")
    
    # Set different modes and colors
    send_msg("device_1|MODE:0")      # Dot
    send_msg("device_2|MODE:1")      # Ring
    time.sleep(1)
    
    send_msg("device_1|SIZE:1.5")
    send_msg("device_2|SIZE:2.0")
    
    print("Moving pointers in circles...")
    start_time = time.time()
    while time.time() - start_time < 10:
        elapsed = time.time() - start_time
        
        # Device 1: Small circle
        x1 = 0.5 + 0.2 * math.cos(elapsed * 2)
        y1 = 0.5 + 0.2 * math.sin(elapsed * 2)
        send_msg(f"device_1|{x1:.4f},{y1:.4f},0,1.5,#ff0000ff,1.0,0,0,1.0")
        
        # Device 2: Large circle, opposite direction
        x2 = 0.5 + 0.4 * math.cos(-elapsed * 1.5)
        y2 = 0.5 + 0.4 * math.sin(-elapsed * 1.5)
        send_msg(f"device_2|{x2:.4f},{y2:.4f},1,2.0,#00ff00ff,1.0,0,0,1.0")
        
        time.sleep(0.01) # ~100Hz

    print("Stopping pointers...")
    send_msg("device_1|STOP")
    send_msg("device_2|STOP")
    print("Simulation complete.")

if __name__ == "__main__":
    main()

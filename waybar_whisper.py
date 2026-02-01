#!/usr/bin/env python3
"""
Waybar module for Whisper dictation status
Shows animated recording indicator in waybar
"""
import json
import socket
import sys
import time
from pathlib import Path

SOCKET_PATH = "/tmp/whisper_daemon.sock"
RECORDING_FLAG = "/tmp/whisper_recording"
SERVICE_FILE = Path.home() / ".config/systemd/user/whisper.service"

# Icons with different states (text-based, no emojis)
ICONS = {
    "ready": "●",
    "recording": "● dictation",
    "processing": "dictation",
    "error": "●"
}

# Animation frames for recording - show "● dictation" when recording
RECORDING_FRAMES = ["● dictation", "● dictation", "● dictation", "● dictation"]
frame_index = 0


def get_current_model():
    """Get current model name from systemd service file"""
    try:
        if not SERVICE_FILE.exists():
            return "unknown"
        
        content = SERVICE_FILE.read_text()
        # Extract model path from ExecStart line
        for line in content.split('\n'):
            if 'ExecStart=' in line and '--model' in line:
                # Find --model argument
                parts = line.split('--model')
                if len(parts) > 1:
                    model_path = parts[1].strip().split()[0]
                    # Extract model name from path (e.g., ggml-base.en.bin -> base.en)
                    model_file = Path(model_path).name
                    if model_file.startswith('ggml-') and model_file.endswith('.bin'):
                        return model_file[5:-4]  # Remove 'ggml-' prefix and '.bin' suffix
        return "unknown"
    except:
        return "unknown"


def get_daemon_status():
    """Check daemon status via socket"""
    if not Path(SOCKET_PATH).exists():
        return "error"
    
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(0.5)
        sock.connect(SOCKET_PATH)
        sock.send(b"STATUS")
        response = sock.recv(1024).decode().strip()
        sock.close()
        
        if response == "RECORDING":
            return "recording"
        elif response == "READY":
            return "ready"
        else:
            return "error"
    except:
        return "error"


def get_waybar_output():
    """Generate waybar JSON output"""
    global frame_index
    
    status = get_daemon_status()
    model = get_current_model()
    
    # Check recording flag file for processing state
    if Path(RECORDING_FLAG).exists() and status == "READY":
        status = "processing"
    
    # Determine icon and tooltip
    if status == "recording":
        # Animate while recording
        icon = RECORDING_FRAMES[frame_index % len(RECORDING_FRAMES)]
        frame_index += 1
        tooltip = f"Recording... (SUPER+D to stop)\nModel: {model}\nRight-click to switch model"
        css_class = "recording"
    elif status == "processing":
        icon = ICONS["processing"]
        tooltip = f"Processing transcription...\nModel: {model}\nRight-click to switch model"
        css_class = "processing"
    elif status == "ready":
        icon = ICONS["ready"]
        tooltip = f"Ready (SUPER+D to start)\nModel: {model}\nRight-click to switch model"
        css_class = "ready"
    else:
        icon = ICONS["error"]
        tooltip = f"Daemon not running\nModel: {model}"
        css_class = "error"
    
    output = {
        "text": icon,
        "tooltip": tooltip,
        "class": css_class
    }
    
    return json.dumps(output)


def main():
    """Main loop for waybar module"""
    try:
        while True:
            print(get_waybar_output(), flush=True)
            time.sleep(0.5)  # Update every 500ms for animation
    except KeyboardInterrupt:
        pass
    except BrokenPipeError:
        pass


if __name__ == "__main__":
    main()

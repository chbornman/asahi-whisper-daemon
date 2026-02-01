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
STREAMING_FLAG = "/tmp/whisper_streaming"
SERVICE_FILE = Path.home() / ".config/systemd/user/whisper.service"

# Icons with different states (text-based, no emojis)
# Will be set based on server mode
ICONS = {}
RECORDING_FRAMES = []
frame_index = 0

def get_server_mode():
    """Check if daemon is running in server mode"""
    try:
        if not SERVICE_FILE.exists():
            return False
        
        content = SERVICE_FILE.read_text()
        return '--server-mode' in content
    except:
        return False

def is_streaming():
    """Check if streaming mode is active"""
    return Path(STREAMING_FLAG).exists()

def update_icons():
    """Update icons based on server mode and streaming"""
    global ICONS, RECORDING_FRAMES
    
    # Streaming mode overrides server/CLI mode
    if is_streaming():
        icon = "〰 streaming"
        ICONS = {
            "ready": icon,
            "recording": icon,
            "processing": icon,
            "error": "〰"
        }
        RECORDING_FRAMES = [icon] * 4
    else:
        is_server = get_server_mode()
        ready_icon = "◆" if is_server else "🎙"
        recording_icon = "◆" if is_server else "●"
        
        ICONS = {
            "ready": ready_icon,
            "recording": f"{recording_icon} dictation",
            "processing": "dictation",
            "error": ready_icon
        }
        
        RECORDING_FRAMES = [f"{recording_icon} dictation"] * 4


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
    
    # Update icons based on current mode
    update_icons()
    
    # Check if streaming
    streaming = is_streaming()
    
    if streaming:
        # Streaming mode - show stream icon always
        icon = ICONS["ready"]
        tooltip = f"▶ Streaming (VAD mode)\nModel: base.en (streaming)\nSUPER+Shift+D: stop stream"
        css_class = "streaming"
    else:
        # Normal daemon mode
        status = get_daemon_status()
        model = get_current_model()
        is_server = get_server_mode()
        mode_text = "Server (model in memory)" if is_server else "CLI (loads each time)"
        
        # Check recording flag file for processing state
        if Path(RECORDING_FLAG).exists() and status == "READY":
            status = "processing"
        
        # Determine icon and tooltip
        if status == "recording":
            # Animate while recording
            icon = RECORDING_FRAMES[frame_index % len(RECORDING_FRAMES)]
            frame_index += 1
            tooltip = f"Recording... (SUPER+D to stop)\nModel: {model}\nMode: {mode_text}\nRight-click: switch model | SUPER+Shift+D: start stream"
            css_class = "recording"
        elif status == "processing":
            icon = ICONS["processing"]
            tooltip = f"Processing transcription...\nModel: {model}\nMode: {mode_text}\nRight-click: switch model | SUPER+Shift+D: start stream"
            css_class = "processing"
        elif status == "ready":
            icon = ICONS["ready"]
            tooltip = f"Ready (SUPER+D to start)\nModel: {model}\nMode: {mode_text}\nRight-click: switch model | SUPER+Shift+D: start stream"
            css_class = "ready"
        else:
            icon = ICONS["error"]
            tooltip = f"Daemon not running\nModel: {model}\nMode: {mode_text}"
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

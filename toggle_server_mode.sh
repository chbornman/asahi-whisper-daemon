#!/usr/bin/env bash
# toggle_server_mode.sh - Toggle between CLI and Server mode with model switching

SERVICE_FILE="$HOME/.config/systemd/user/whisper.service"
WHISPER_MODELS_DIR="$HOME/projects/whisper.cpp/models"

# Default models for each mode
CLI_MODEL="base.en"
SERVER_MODEL="small.en"  # Change to large-v3-turbo if you want

if [ ! -f "$SERVICE_FILE" ]; then
    notify-send "Whisper Mode" "Service file not found" -u critical -t 2000
    exit 1
fi

# Check current mode
if grep -q "\-\-server-mode" "$SERVICE_FILE"; then
    # Currently in server mode, switch to CLI mode with base.en
    sed -i 's/ --server-mode//' "$SERVICE_FILE"
    sed -i "s|/models/ggml-[^/]*\.bin|/models/ggml-${CLI_MODEL}.bin|" "$SERVICE_FILE"
    MODE="CLI"
    MODEL="$CLI_MODEL"
    ICON="●"
else
    # Currently in CLI mode, switch to server mode with server model
    # First check if server model is downloaded
    if [ ! -f "$WHISPER_MODELS_DIR/ggml-$SERVER_MODEL.bin" ]; then
        notify-send "Whisper Mode" "Downloading $SERVER_MODEL model..." -t 3000
        cd "$WHISPER_MODELS_DIR" && ./download-ggml-model.sh "$SERVER_MODEL"
        if [ $? -ne 0 ]; then
            notify-send "Whisper Mode" "Failed to download $SERVER_MODEL" -u critical -t 3000
            exit 1
        fi
    fi
    
    sed -i 's/--no-notifications/--no-notifications --server-mode/' "$SERVICE_FILE"
    sed -i "s|/models/ggml-[^/]*\.bin|/models/ggml-${SERVER_MODEL}.bin|" "$SERVICE_FILE"
    MODE="Server"
    MODEL="$SERVER_MODEL"
    ICON="◆"
fi

# Restart daemon
systemctl --user daemon-reload
systemctl --user restart whisper.service

# Wait a moment for restart
sleep 1

# Check if service started successfully
if systemctl --user is-active --quiet whisper.service; then
    notify-send "Whisper Mode" "$ICON Switched to $MODE mode with $MODEL" -t 2000
else
    notify-send "Whisper Mode" "Failed to restart daemon" -u critical -t 3000
fi

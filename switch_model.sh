#!/usr/bin/env bash
# switch_model.sh - Interactive model switcher for whisper daemon

set -e

WHISPER_MODELS_DIR="$HOME/projects/whisper.cpp/models"
SERVICE_FILE="$HOME/.config/systemd/user/whisper.service"

# Get current model from systemd service
get_current_model() {
    if [ ! -f "$SERVICE_FILE" ]; then
        echo ""
        return
    fi
    
    # Extract model path from ExecStart line
    grep "ExecStart=" "$SERVICE_FILE" | sed -n 's/.*--model \([^ ]*\).*/\1/p' | xargs basename 2>/dev/null || echo ""
}

# List all available whisper models
list_all_models() {
    cat <<EOF
tiny.en
base.en
small.en
medium.en
large-v3
large-v3-turbo
tiny
base
small
medium
large-v2
EOF
}

# Check if model is downloaded
is_downloaded() {
    local model=$1
    [ -f "$WHISPER_MODELS_DIR/ggml-$model.bin" ]
}

# Get current model
current_model=$(get_current_model)
current_model_name=$(echo "$current_model" | sed 's/ggml-\(.*\)\.bin/\1/')

# Build menu items
menu_items=""
while IFS= read -r model; do
    if is_downloaded "$model"; then
        if [ "$model" = "$current_model_name" ]; then
            # Current model - show with filled circle
            menu_items="${menu_items}● ${model} (active)\n"
        else
            # Downloaded but not active - show with checkmark
            menu_items="${menu_items}✓ ${model}\n"
        fi
    else
        # Not downloaded - show plain
        menu_items="${menu_items}  ${model}\n"
    fi
done < <(list_all_models)

# Add separator and options
menu_items="${menu_items}---\n"

# Check current mode
if grep -q "\-\-server-mode" "$SERVICE_FILE"; then
    menu_items="${menu_items}◆ Toggle to CLI mode (loads model each time)\n"
else
    menu_items="${menu_items}● Toggle to Server mode (keeps model in memory)\n"
fi

menu_items="${menu_items}📥 Download more models...\n"

# Show wofi menu
selected=$(echo -e "$menu_items" | wofi --dmenu --prompt "Select Whisper Model" --width 450 --height 450 --insensitive)

# Exit if nothing selected
if [ -z "$selected" ]; then
    exit 0
fi

# Handle "Toggle to Server/CLI mode" option
if echo "$selected" | grep -q "Toggle to"; then
    exec ~/projects/asahi-whisper-daemon/toggle_server_mode.sh
fi

# Handle "Download more models" option
if echo "$selected" | grep -q "Download more models"; then
    # Open terminal with download script help
    foot -e bash -c "cd $WHISPER_MODELS_DIR && ./download-ggml-model.sh; echo ''; echo 'Press Enter to close...'; read"
    exit 0
fi

# Extract model name from selection (remove symbols and status text)
selected_model=$(echo "$selected" | sed 's/^[●✓ ]*//' | sed 's/ (active)$//' | xargs)

# Check if already current
if [ "$selected_model" = "$current_model_name" ]; then
    notify-send "Whisper Model" "Already using $selected_model" -t 2000
    exit 0
fi

# Check if model needs to be downloaded
if ! is_downloaded "$selected_model"; then
    # Download the model
    notify-send "Whisper Model" "Downloading $selected_model..." -t 3000
    
    if foot -e bash -c "cd $WHISPER_MODELS_DIR && ./download-ggml-model.sh $selected_model && echo '' && echo 'Download complete! Press Enter to close...' && read"; then
        notify-send "Whisper Model" "Downloaded $selected_model successfully" -t 2000
    else
        notify-send "Whisper Model" "Failed to download $selected_model" -u critical -t 3000
        exit 1
    fi
fi

# Update systemd service file
model_path="$WHISPER_MODELS_DIR/ggml-$selected_model.bin"

if [ ! -f "$SERVICE_FILE" ]; then
    notify-send "Whisper Model" "Service file not found: $SERVICE_FILE" -u critical -t 3000
    exit 1
fi

# Backup service file
cp "$SERVICE_FILE" "$SERVICE_FILE.backup.$(date +%Y%m%d_%H%M%S)"

# Update the model path in ExecStart
sed -i "s|--model [^ ]*|--model $model_path|" "$SERVICE_FILE"

# Reload and restart service
systemctl --user daemon-reload
systemctl --user restart whisper.service

# Check if service started successfully
sleep 0.5
if systemctl --user is-active --quiet whisper.service; then
    notify-send "Whisper Model" "Switched to $selected_model" -t 2000
else
    notify-send "Whisper Model" "Failed to restart service - check logs" -u critical -t 3000
    journalctl --user -u whisper.service -n 20
    exit 1
fi

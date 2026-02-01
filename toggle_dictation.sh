#!/bin/bash
# Toggle whisper dictation (similar to margo)
# Single key press to start/stop

SOCKET_PATH="/tmp/whisper_daemon.sock"
RECORDING_FLAG="/tmp/whisper_recording"

# Check if daemon is running
if [ ! -S "$SOCKET_PATH" ]; then
    notify-send -u critical "🎤 Whisper" "Daemon not running! Start it first."
    exit 1
fi

# Send toggle command to daemon
echo "TOGGLE" | ncat -U "$SOCKET_PATH"

# Exit code doesn't matter - daemon handles it
exit 0

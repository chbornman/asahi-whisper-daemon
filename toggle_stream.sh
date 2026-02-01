#!/usr/bin/env bash
# toggle_stream.sh - Toggle live streaming transcription mode

STREAM_FLAG="/tmp/whisper_streaming"
STREAM_PID_FILE="/tmp/whisper_stream.pid"
SOUND_DIR="$HOME/projects/asahi-whisper-daemon/sounds"
WHISPER_STREAM="$HOME/projects/whisper.cpp/build/bin/whisper-stream"
MODEL="$HOME/projects/whisper.cpp/models/ggml-base.en.bin"

# Check if already streaming
if [ -f "$STREAM_FLAG" ]; then
    # Stop streaming
    if [ -f "$STREAM_PID_FILE" ]; then
        PID=$(cat "$STREAM_PID_FILE")
        kill $PID 2>/dev/null
        # Also kill any child processes
        pkill -P $PID 2>/dev/null
        rm -f "$STREAM_PID_FILE"
    fi
    
    # Kill any lingering whisper-stream processes
    pkill -f "whisper-stream.*base.en"
    
    # Remove flag
    rm -f "$STREAM_FLAG"
    
    # Play stop sound
    if [ -f "$SOUND_DIR/hihat.wav" ]; then
        pw-play "$SOUND_DIR/hihat.wav" &
    fi
    
    notify-send "Whisper Stream" "▶ Streaming stopped" -t 1500
else
    # Start streaming
    
    # Play start sound and wait for it to finish
    if [ -f "$SOUND_DIR/snare.wav" ]; then
        pw-play "$SOUND_DIR/snare.wav"
        sleep 0.3  # Wait for sound to finish
    fi
    
    # Create flag
    touch "$STREAM_FLAG"
    
    # Start whisper-stream in background
    # VAD mode: --step 0 means wait for speech, -vth 0.6 is voice threshold
    # Type each transcription chunk separately with wtype
    (
        "$WHISPER_STREAM" \
            -m "$MODEL" \
            --step 0 \
            --length 30000 \
            --keep 0 \
            -vth 0.6 \
            -t 4 \
            2>/tmp/whisper_stream.log \
            | {
                last_text=""
                in_transcription=false
                
                while IFS= read -r line; do
                    # Detect start of transcription block
                    if echo "$line" | grep -q "^### Transcription.*START"; then
                        in_transcription=true
                        last_text=""
                    # Detect end of transcription block
                    elif echo "$line" | grep -q "^### Transcription.*END"; then
                        in_transcription=false
                        # Type the last captured text from this block
                        if [ -n "$last_text" ]; then
                            wtype "$last_text "
                        fi
                        last_text=""
                    # Capture timestamp lines (actual transcriptions)
                    elif [ "$in_transcription" = true ] && echo "$line" | grep -q "^\[.*\]"; then
                        # Extract text after the timestamp bracket
                        text=$(echo "$line" | sed 's/^\[.*\] *//')
                        text=$(echo "$text" | xargs)
                        # Keep updating last_text (we want the final/longest one)
                        if [ -n "$text" ]; then
                            last_text="$text"
                        fi
                    fi
                done
            }
    ) &
    
    # Save PID
    echo $! > "$STREAM_PID_FILE"
    
    notify-send "Whisper Stream" "▶ Streaming started (VAD mode)" -t 1500
fi

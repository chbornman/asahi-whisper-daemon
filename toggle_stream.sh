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
    
    # Create flag first
    touch "$STREAM_FLAG"
    
    # Play start sound in background (don't wait)
    if [ -f "$SOUND_DIR/snare.wav" ]; then
        pw-play "$SOUND_DIR/snare.wav" &
    fi
    
    # Start whisper-stream in background
    # VAD mode: --step 0 means wait for speech, -vth 0.6 is voice threshold
    # Type each transcription chunk separately with wtype
    (
        "$WHISPER_STREAM" \
            -m "$MODEL" \
            --step 0 \
            --length 30000 \
            --keep 200 \
            -vth 0.6 \
            -t 8 \
            2>/tmp/whisper_stream.log \
            | tee /tmp/whisper_stream_output.log \
            | {
                # Track what we've actually typed (committed), not what whisper said
                committed_text=""
                current_full_text=""
                in_transcription=false
                fallback_count=0  # Track consecutive fallbacks to detect drift
                
                # Helper: normalize text for comparison (lowercase, collapse spaces, remove some punctuation)
                normalize() {
                    echo "$1" | tr '[:upper:]' '[:lower:]' | tr -s ' ' | sed 's/^ *//;s/ *$//'
                }
                
                while IFS= read -r line; do
                    # Detect start of transcription block
                    if echo "$line" | grep -q "^### Transcription.*START"; then
                        in_transcription=true
                        current_full_text=""
                        
                    # Detect end of transcription block
                    elif echo "$line" | grep -q "^### Transcription.*END"; then
                        in_transcription=false
                        
                        if [ -n "$current_full_text" ]; then
                            echo "[DEBUG] current_full_text: '$current_full_text'" >> /tmp/whisper_stream_debug.log
                            echo "[DEBUG] committed_text: '$committed_text'" >> /tmp/whisper_stream_debug.log
                            
                            new_text=""
                            
                            if [ -z "$committed_text" ]; then
                                # First transcription - type everything
                                new_text="$current_full_text"
                                echo "[DEBUG] First transcription, typing all" >> /tmp/whisper_stream_debug.log
                            else
                                # Find where committed_text appears in current_full_text
                                # We look for the longest suffix of committed that's a prefix of current
                                
                                committed_norm=$(normalize "$committed_text")
                                current_norm=$(normalize "$current_full_text")
                                
                                found_overlap=false
                                
                                # Strategy: try progressively shorter suffixes of committed_text
                                # until we find one that appears at the START of current_full_text
                                committed_len=${#committed_norm}
                                
                                # Minimum overlap to consider (characters)
                                min_overlap=20
                                
                                for (( cut=0; cut<committed_len-min_overlap; cut+=10 )); do
                                    suffix="${committed_norm:cut}"
                                    suffix_len=${#suffix}
                                    
                                    # Check if current starts with this suffix
                                    current_prefix="${current_norm:0:suffix_len}"
                                    
                                    if [ "$suffix" = "$current_prefix" ]; then
                                        # Found overlap! Everything after suffix_len in current is new
                                        # But we need to work with original (non-normalized) text
                                        # Use the character count ratio to estimate position
                                        
                                        original_current_len=${#current_full_text}
                                        ratio_pos=$(( (suffix_len * original_current_len) / ${#current_norm} ))
                                        
                                        # Get text from this position
                                        new_text="${current_full_text:ratio_pos}"
                                        
                                        # Only trim partial word if we landed mid-word (first char is not space)
                                        first_char="${new_text:0:1}"
                                        if [[ "$first_char" != " " && "$first_char" != "" ]]; then
                                            # Check if char before ratio_pos was a space (word boundary)
                                            if [ "$ratio_pos" -gt 0 ]; then
                                                char_before="${current_full_text:ratio_pos-1:1}"
                                                if [[ "$char_before" != " " ]]; then
                                                    # Mid-word, skip to next word
                                                    new_text=$(echo "$new_text" | sed 's/^[^ ]* //')
                                                fi
                                            fi
                                        fi
                                        new_text="${new_text#"${new_text%%[![:space:]]*}"}"
                                        
                                        found_overlap=true
                                        fallback_count=0  # Reset fallback counter on successful match
                                        echo "[DEBUG] Found overlap (cut=$cut, suffix_len=$suffix_len, ratio_pos=$ratio_pos) -> new: '$new_text'" >> /tmp/whisper_stream_debug.log
                                        break
                                    fi
                                done
                                
                                if [ "$found_overlap" = false ]; then
                                    # No overlap found - check if current contains end of committed
                                    # (handles case where whisper completely re-did the transcription)
                                    
                                    # Take last 50 chars of committed and search for it in current
                                    if [ "$committed_len" -gt 50 ]; then
                                        search_suffix="${committed_norm: -50}"
                                    else
                                        search_suffix="$committed_norm"
                                    fi
                                    
                                    # Find position in current
                                    pos=$(echo "$current_norm" | grep -bo "$search_suffix" | tail -1 | cut -d: -f1)
                                    
                                    if [ -n "$pos" ]; then
                                        # Found it! Calculate where new content starts
                                        new_start=$((pos + ${#search_suffix}))
                                        original_current_len=${#current_full_text}
                                        ratio_pos=$(( (new_start * original_current_len) / ${#current_norm} ))
                                        
                                        new_text="${current_full_text:ratio_pos}"
                                        
                                        # Only trim partial word if we landed mid-word
                                        if [ "$ratio_pos" -gt 0 ]; then
                                            char_before="${current_full_text:ratio_pos-1:1}"
                                            first_char="${new_text:0:1}"
                                            if [[ "$char_before" != " " && "$first_char" != " " && "$first_char" != "" ]]; then
                                                # Mid-word, skip to next word
                                                new_text=$(echo "$new_text" | sed 's/^[^ ]* //')
                                            fi
                                        fi
                                        new_text="${new_text#"${new_text%%[![:space:]]*}"}"
                                        
                                        fallback_count=0  # Reset on successful match
                                        echo "[DEBUG] Found committed suffix in current at pos $pos, ratio_pos=$ratio_pos -> new: '$new_text'" >> /tmp/whisper_stream_debug.log
                                    else
                                        # Complete mismatch - committed_text has drifted from reality
                                        fallback_count=$((fallback_count + 1))
                                        echo "[DEBUG] No overlap found (fallback_count=$fallback_count)" >> /tmp/whisper_stream_debug.log
                                        
                                        if [ "$fallback_count" -ge 2 ]; then
                                            # Too many fallbacks - committed_text is out of sync
                                            # Reset to current and just type the last new bit
                                            echo "[DEBUG] Resetting committed_text due to drift" >> /tmp/whisper_stream_debug.log
                                            
                                            # Only type truly new content (last sentence)
                                            last_sentence=$(echo "$current_full_text" | sed 's/.*[.!?] //')
                                            if [ ${#last_sentence} -lt ${#current_full_text} ] && [ ${#last_sentence} -lt 100 ]; then
                                                new_text="$last_sentence"
                                            else
                                                # Skip typing, just reset
                                                new_text=""
                                            fi
                                            
                                            # Reset committed to match current whisper state
                                            committed_text="$current_full_text"
                                            fallback_count=0
                                        else
                                            # First fallback - try conservative approach
                                            last_sentence=$(echo "$current_full_text" | sed 's/.*[.!?] //')
                                            if [ ${#last_sentence} -lt ${#current_full_text} ]; then
                                                new_text="$last_sentence"
                                            else
                                                # No sentence break - take last 50 chars at word boundary
                                                if [ ${#current_full_text} -gt 60 ]; then
                                                    new_text="${current_full_text: -60}"
                                                    new_text=$(echo "$new_text" | sed 's/^[^ ]* //')
                                                else
                                                    new_text="$current_full_text"
                                                fi
                                            fi
                                        fi
                                        echo "[DEBUG] Fallback new_text: '$new_text'" >> /tmp/whisper_stream_debug.log
                                    fi
                                fi
                            fi
                            
                            # Type the new text
                            if [ -n "$new_text" ]; then
                                echo "[DEBUG] Typing: '$new_text '" >> /tmp/whisper_stream_debug.log
                                if wtype "$new_text " 2>> /tmp/whisper_stream_debug.log; then
                                    echo "[DEBUG] wtype succeeded" >> /tmp/whisper_stream_debug.log
                                    # Append to committed text (what we've actually typed)
                                    if [ -n "$committed_text" ]; then
                                        committed_text="$committed_text $new_text"
                                    else
                                        committed_text="$new_text"
                                    fi
                                else
                                    echo "[DEBUG] wtype FAILED with exit code $?" >> /tmp/whisper_stream_debug.log
                                fi
                            else
                                echo "[DEBUG] new_text is empty, skipping wtype" >> /tmp/whisper_stream_debug.log
                            fi
                            
                            # Trim committed_text if it gets too long (keep last 500 chars)
                            if [ ${#committed_text} -gt 500 ]; then
                                committed_text="${committed_text: -500}"
                                # Trim to word boundary
                                committed_text=$(echo "$committed_text" | sed 's/^[^ ]* //')
                                echo "[DEBUG] Trimmed committed_text to last 500 chars" >> /tmp/whisper_stream_debug.log
                            fi
                        fi
                        
                    # Capture timestamp lines (actual transcriptions)
                    elif [ "$in_transcription" = true ] && echo "$line" | grep -q "^\[.*\]"; then
                        # Extract text after the timestamp bracket
                        text=$(echo "$line" | sed 's/^\[.*\] *//')
                        text="${text#"${text%%[![:space:]]*}"}"
                        text="${text%"${text##*[![:space:]]}"}"
                        
                        echo "[DEBUG] Captured: '$text'" >> /tmp/whisper_stream_debug.log
                        
                        # Filter out noise artifacts
                        if echo "$text" | grep -qiE '^\s*(\(.*\)|\[.*\]|\*.*\*)\s*$'; then
                            echo "[DEBUG] Filtered noise: '$text'" >> /tmp/whisper_stream_debug.log
                            text=""
                        fi
                        
                        if [ -n "$text" ]; then
                            if [ -n "$current_full_text" ]; then
                                current_full_text="$current_full_text $text"
                            else
                                current_full_text="$text"
                            fi
                        fi
                    fi
                done
            }
    ) &
    
    # Save PID
    echo $! > "$STREAM_PID_FILE"
    
    notify-send "Whisper Stream" "▶ Streaming started (VAD mode)" -t 1500
fi

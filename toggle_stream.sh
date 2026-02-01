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
                previous_full_text=""
                current_full_text=""
                in_transcription=false
                last_transcription_time=0
                
                while IFS= read -r line; do
                    # Detect start of transcription block
                    if echo "$line" | grep -q "^### Transcription.*START"; then
                        in_transcription=true
                        current_full_text=""
                        
                        # Extract timestamps to detect long silence gaps
                        # Format: ### Transcription N START | t0 = 123 ms | t1 = 456 ms
                        if echo "$line" | grep -q "t0 ="; then
                            current_t0=$(echo "$line" | sed -n 's/.*t0 = \([0-9]*\) ms.*/\1/p')
                            current_t1=$(echo "$line" | sed -n 's/.*t1 = \([0-9]*\) ms.*/\1/p')
                            
                            # Check if there was a long silence (10+ seconds = 10000ms)
                            # Gap is measured from when last transcription ended (t1) to when this one started (t0)
                            if [ -n "$last_transcription_time" ] && [ "$last_transcription_time" -gt 0 ]; then
                                silence_gap=$((current_t0 - last_transcription_time))
                                if [ "$silence_gap" -gt 10000 ]; then
                                    echo "[DEBUG] Long silence detected (${silence_gap}ms), resetting context" >> /tmp/whisper_stream_debug.log
                                    previous_full_text=""
                                fi
                            fi
                            
                            # Update last transcription time to current t1 (end of this block)
                            last_transcription_time="$current_t1"
                        fi
                    # Detect end of transcription block
                    elif echo "$line" | grep -q "^### Transcription.*END"; then
                        in_transcription=false
                        
                        # Extract t1 from the previous START line for silence detection
                        # (We already captured it when we saw the START line)
                        
                        # Remove the previously typed portion to get only NEW text
                        if [ -n "$current_full_text" ]; then
                            # Debug logging
                            echo "[DEBUG] current_full_text: '$current_full_text'" >> /tmp/whisper_stream_debug.log
                            echo "[DEBUG] previous_full_text: '$previous_full_text'" >> /tmp/whisper_stream_debug.log
                            
                            if [ -n "$previous_full_text" ]; then
                                # Smart diff: Find longest common suffix of previous with prefix of current
                                # This handles buffer shifts where the beginning is dropped
                                
                                # First try simple prefix match (fastest)
                                if [[ "$current_full_text" == "$previous_full_text"* ]]; then
                                    new_text="${current_full_text#"$previous_full_text"}"
                                    # Trim whitespace
                                    new_text="${new_text#"${new_text%%[![:space:]]*}"}"
                                    new_text="${new_text%"${new_text##*[![:space:]]}"}"
                                    echo "[DEBUG] Simple prefix match, new_text: '$new_text'" >> /tmp/whisper_stream_debug.log
                                else
                                    # Prefix doesn't match - find overlap using fuzzy word-based matching
                                    # Strip punctuation from words for comparison, but keep original text
                                    
                                    # Split previous and current into words
                                    IFS=' ' read -ra prev_words <<< "$previous_full_text"
                                    IFS=' ' read -ra curr_words <<< "$current_full_text"
                                    overlap_found=false
                                    
                                    # Try to find the longest suffix of previous that matches a prefix of current
                                    # We'll do fuzzy matching by comparing words without trailing punctuation
                                    # Require minimum overlap of 5 words to avoid false positives
                                    min_overlap_words=5
                                    
                                    for (( i=${#prev_words[@]}-1; i>=0; i-- )); do
                                        # Extract suffix of previous words starting at position i
                                        prev_suffix_words=("${prev_words[@]:i}")
                                        prev_suffix_len=${#prev_suffix_words[@]}
                                        
                                        # Skip if overlap is too short (avoid matching single words)
                                        if [ "$prev_suffix_len" -lt "$min_overlap_words" ]; then
                                            continue
                                        fi
                                        
                                        # Check if current has enough words to match
                                        if [ "$prev_suffix_len" -gt "${#curr_words[@]}" ]; then
                                            continue
                                        fi
                                        
                                        # Compare the suffix words with current words (fuzzy match with tolerance)
                                        # Allow up to 2 word mismatches in the sequence
                                        mismatch_count=0
                                        max_mismatches=2
                                        match=true
                                        
                                        for (( j=0; j<prev_suffix_len; j++ )); do
                                            # Strip ALL punctuation and normalize for comparison
                                            # But keep original words for typing
                                            prev_word="${prev_suffix_words[j]}"
                                            curr_word="${curr_words[j]}"
                                            
                                            # Remove all punctuation (not just trailing), collapse whitespace, lowercase
                                            prev_word_clean=$(echo "$prev_word" | tr -d '.,;:!?"""'\''()[]{}…—–-' | tr '[:upper:]' '[:lower:]' | tr -s ' ')
                                            curr_word_clean=$(echo "$curr_word" | tr -d '.,;:!?"""'\''()[]{}…—–-' | tr '[:upper:]' '[:lower:]' | tr -s ' ')
                                            
                                            # Skip empty words (pure punctuation like "..." or "...")
                                            if [ -z "$prev_word_clean" ] || [ -z "$curr_word_clean" ]; then
                                                continue
                                            fi
                                            
                                            if [ "$prev_word_clean" != "$curr_word_clean" ]; then
                                                mismatch_count=$((mismatch_count + 1))
                                                if [ "$mismatch_count" -gt "$max_mismatches" ]; then
                                                    match=false
                                                    break
                                                fi
                                            fi
                                        done
                                        
                                        if [ "$match" = true ]; then
                                            echo "[DEBUG] Fuzzy match with $mismatch_count mismatches (tolerance: $max_mismatches)" >> /tmp/whisper_stream_debug.log
                                            # Found fuzzy match! Calculate how many words to skip in current
                                            # Reconstruct the actual overlapping text from current (preserving punctuation)
                                            overlap_words=("${curr_words[@]:0:prev_suffix_len}")
                                            remaining_words=("${curr_words[@]:prev_suffix_len}")
                                            
                                            # Join remaining words back into text
                                            new_text="${remaining_words[*]}"
                                            new_text="${new_text#"${new_text%%[![:space:]]*}"}"
                                            new_text="${new_text%"${new_text##*[![:space:]]}"}"
                                            overlap_found=true
                                            echo "[DEBUG] Found fuzzy overlap at word $i (${prev_suffix_len} words matched) -> new_text: '$new_text'" >> /tmp/whisper_stream_debug.log
                                            break
                                        fi
                                    done
                                    
                                    # If forward search didn't find overlap, try bidirectional search
                                    # Search for any suffix of current that appears in previous
                                    if [ "$overlap_found" = false ]; then
                                        echo "[DEBUG] Forward search failed, trying bidirectional search..." >> /tmp/whisper_stream_debug.log
                                        
                                        for (( i=${#curr_words[@]}-1; i>=0; i-- )); do
                                            # Extract suffix of current words starting at position i
                                            curr_suffix_words=("${curr_words[@]:i}")
                                            curr_suffix_len=${#curr_suffix_words[@]}
                                            
                                            # Skip if overlap is too short
                                            if [ "$curr_suffix_len" -lt "$min_overlap_words" ]; then
                                                continue
                                            fi
                                            
                                            # Search for this suffix anywhere in previous text
                                            # Try each position in previous text
                                            for (( k=0; k<=${#prev_words[@]}-curr_suffix_len; k++ )); do
                                                # Extract candidate from previous
                                                prev_candidate_words=("${prev_words[@]:k:curr_suffix_len}")
                                                
                                                # Compare with fuzzy matching
                                                mismatch_count=0
                                                max_mismatches=2
                                                match=true
                                                
                                                for (( j=0; j<curr_suffix_len; j++ )); do
                                                    prev_word="${prev_candidate_words[j]}"
                                                    curr_word="${curr_suffix_words[j]}"
                                                    
                                                    # Normalize both words
                                                    prev_word_clean=$(echo "$prev_word" | tr -d '.,;:!?"""'\''()[]{}…—–-' | tr '[:upper:]' '[:lower:]' | tr -s ' ')
                                                    curr_word_clean=$(echo "$curr_word" | tr -d '.,;:!?"""'\''()[]{}…—–-' | tr '[:upper:]' '[:lower:]' | tr -s ' ')
                                                    
                                                    # Skip empty words
                                                    if [ -z "$prev_word_clean" ] || [ -z "$curr_word_clean" ]; then
                                                        continue
                                                    fi
                                                    
                                                    if [ "$prev_word_clean" != "$curr_word_clean" ]; then
                                                        mismatch_count=$((mismatch_count + 1))
                                                        if [ "$mismatch_count" -gt "$max_mismatches" ]; then
                                                            match=false
                                                            break
                                                        fi
                                                    fi
                                                done
                                                
                                                if [ "$match" = true ]; then
                                                    # Found overlap! Everything BEFORE position i in current is new
                                                    new_words=("${curr_words[@]:0:i}")
                                                    new_text="${new_words[*]}"
                                                    new_text="${new_text#"${new_text%%[![:space:]]*}"}"
                                                    new_text="${new_text%"${new_text##*[![:space:]]}"}"
                                                    overlap_found=true
                                                    echo "[DEBUG] Bidirectional match: found suffix at position $i of current matching position $k of previous (${curr_suffix_len} words, $mismatch_count mismatches)" >> /tmp/whisper_stream_debug.log
                                                    echo "[DEBUG] New text from bidirectional: '$new_text'" >> /tmp/whisper_stream_debug.log
                                                    break 2  # Break out of both loops
                                                fi
                                            done
                                        done
                                    fi
                                    
                                    if [ "$overlap_found" = false ]; then
                                        # No overlap found even with bidirectional search - type everything
                                        new_text="$current_full_text"
                                        echo "[DEBUG] No overlap found (tried both directions), typing everything: '$new_text'" >> /tmp/whisper_stream_debug.log
                                    fi
                                fi
                            else
                                # No previous text - type everything
                                new_text="$current_full_text"
                                echo "[DEBUG] First transcription, typing everything: '$new_text'" >> /tmp/whisper_stream_debug.log
                            fi
                            
                            # Type the new text
                            if [ -n "$new_text" ]; then
                                echo "[DEBUG] Typing: '$new_text '" >> /tmp/whisper_stream_debug.log
                                if wtype "$new_text " 2>> /tmp/whisper_stream_debug.log; then
                                    echo "[DEBUG] wtype succeeded" >> /tmp/whisper_stream_debug.log
                                else
                                    echo "[DEBUG] wtype FAILED with exit code $?" >> /tmp/whisper_stream_debug.log
                                fi
                            else
                                echo "[DEBUG] new_text is empty, skipping wtype" >> /tmp/whisper_stream_debug.log
                            fi
                            
                            # Update previous text for next iteration
                            previous_full_text="$current_full_text"
                        fi
                    # Capture timestamp lines (actual transcriptions)
                    elif [ "$in_transcription" = true ] && echo "$line" | grep -q "^\[.*\]"; then
                        # Extract text after the timestamp bracket
                        text=$(echo "$line" | sed 's/^\[.*\] *//')
                        # Trim leading/trailing whitespace without xargs (which breaks on quotes)
                        text="${text#"${text%%[![:space:]]*}"}"  # Remove leading whitespace
                        text="${text%"${text##*[![:space:]]}"}"  # Remove trailing whitespace
                        
                        echo "[DEBUG] Captured timestamp line: '$line'" >> /tmp/whisper_stream_debug.log
                        echo "[DEBUG] Extracted text: '$text'" >> /tmp/whisper_stream_debug.log
                        
                        # Accumulate all text with spaces
                        if [ -n "$text" ]; then
                            if [ -n "$current_full_text" ]; then
                                current_full_text="$current_full_text $text"
                            else
                                current_full_text="$text"
                            fi
                            echo "[DEBUG] Updated current_full_text: '$current_full_text'" >> /tmp/whisper_stream_debug.log
                        fi
                    fi
                done
            }
    ) &
    
    # Save PID
    echo $! > "$STREAM_PID_FILE"
    
    notify-send "Whisper Stream" "▶ Streaming started (VAD mode)" -t 1500
fi

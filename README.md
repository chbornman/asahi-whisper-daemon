# Asahi Whisper Daemon

Voice dictation system using whisper.cpp for Asahi Linux on Apple Silicon.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Asahi%20Linux-blue)](https://asahilinux.org/)

## Features

- 🎤 **Three dictation modes**:
  - **CLI Mode (●)** - Press-to-record (SUPER+D)
  - **Server Mode (◆)** - Model stays in memory for faster transcription
  - **Stream Mode (▶)** - Live transcription with Voice Activity Detection
- 📊 **Waybar integration** - Visual mode and status indicators
- 🔊 **Audio feedback** - Snare/hihat sounds for start/stop
- ⚡ **Fast transcription** - 11.5x faster than real-time (base.en)
- 🎛️ **Interactive model switcher** - Right-click menu to change models
- 💾 **Flexible memory usage** - 300 MB (CLI) to 1.7 GB (Server with large models)
- 🚀 **Auto-start** - Systemd service starts on boot
- 🎯 **Optimized for M1/M2/M3/M4** - ARM NEON, FP16, DOTPROD instructions

## Demo

**Waybar Indicator Modes:**
- `〰` - CLI mode ready (loads model each time)
- `◆` - Server mode ready (model in memory)
- `〰 streaming` - Stream mode active (live transcription)

**States:**
- `● dictation` - Currently recording (CLI mode)
- `◆ dictation` - Currently recording (Server mode)
- `dictation` - Processing transcription
- `〰 streaming` - Streaming mode active (VAD listening)

## Requirements

### Hardware
- Apple Silicon Mac (M1, M2, M3, M4, etc.)
- Running [Asahi Linux](https://asahilinux.org/)

### Software
- **Sway** - Wayland compositor
- **Waybar** - Status bar
- **wtype** - Wayland text input tool
- **uv** - Python package manager
- **Build tools** - git, cmake, gcc/g++

### Installing Prerequisites

**Fedora/RHEL:**
```bash
sudo dnf install sway waybar wtype git cmake gcc-c++
```

**Installing uv:**
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

## Installation

### Quick Install

```bash
git clone https://github.com/calebbornman/asahi-whisper-daemon.git
cd asahi-whisper-daemon
./install.sh
```

The install script will:
1. Check for Asahi Linux (warns if not detected)
2. Verify all prerequisites
3. Clone and build whisper.cpp
4. Download the base.en model
5. Create Python virtual environment
6. Install dependencies
7. Configure systemd service
8. Update Sway and Waybar configs
9. Start the daemon

### Installation Options

```bash
./install.sh [OPTIONS]

Options:
  --dry-run          Preview installation without making changes
  --model NAME       Whisper model to download (default: base.en)
  --whisper-dir DIR  Custom whisper.cpp location (default: ~/projects/whisper.cpp)
  --help             Show help message
```

**Examples:**

```bash
# Preview what will be installed
./install.sh --dry-run

# Install with a more accurate model
./install.sh --model small.en

# Custom whisper.cpp location
./install.sh --whisper-dir ~/.local/share/whisper.cpp
```

## Usage

### Three Dictation Modes

The daemon supports three different modes for different use cases:

| Mode | Icon | Keybind | Best For |
|------|------|---------|----------|
| **Stream Mode** | ▶ | SUPER+D (toggle stream) | Live transcription as you speak |
| **CLI Mode** | ● | SUPER+Shift+D (toggle recording) | Quick dictation, lower memory usage |
| **Server Mode** | ◆ | Via menu only | Faster transcription with larger models |

### 1. Live Streaming Mode (▶) - Default

Real-time transcription as you speak using Voice Activity Detection (VAD):

1. **Press SUPER+D** to start streaming
   - Waybar shows: `▶` 
   - Hear: snare sound (starts immediately - no delay!)
2. **Start speaking** - just talk naturally
3. **Pause briefly** - VAD detects silence and transcribes
4. **Text appears** automatically after each pause
5. **Continue speaking** or pause for 10+ seconds to reset context
6. **Press SUPER+D** again to stop streaming
   - Hear: hihat sound

**Streaming Mode Features:**
- ✅ **Instant startup** - No delay before you can speak
- ✅ **Smart deduplication** - Prevents repeated text when buffer shifts
- ✅ **Fuzzy matching** - Handles punctuation changes ("Excellent." vs "Excellent,")
- ✅ **Auto-reset** - Context clears after 10s silence (prevents slowdown)
- ✅ **Handles apostrophes** - "it's", "I'm", "you're" all work perfectly
- ✅ **Long sessions** - Tested for hours of continuous use
- ✅ **Always-on ready** - Leave it running, only uses CPU when speaking
- 🎯 **30-second buffer** - Rolling window with Voice Activity Detection
- 📊 **~300 MB memory** - Constant, doesn't grow over time

### 2. Basic Dictation (CLI Mode) - SUPER+Shift+D

Press-to-record mode for quick dictation:

1. **Open any text field** (editor, browser, terminal, etc.)
2. **Press SUPER+Shift+D** to start recording
   - Waybar shows: `● dictation` (red, golden background)
   - Hear: snare sound (drum hit)
3. **Speak clearly**: "This is a test of the whisper dictation system"
4. **Press SUPER+Shift+D** again to stop
   - Waybar shows: `dictation` (processing)
   - Hear: hihat sound
5. **Wait ~1-2 seconds** → Text appears where your cursor is!

### 3. Server Mode (◆)

Keeps the whisper model loaded in memory for faster transcription:

- **Enable**: Right-click waybar → "Toggle to Server mode"
- **Benefits**: Faster transcription (no model loading time), better for larger models
- **Trade-off**: Uses more RAM (~577 MB for small.en, ~1.7 GB for large-v3-turbo)
- **Usage**: Same as CLI mode (SUPER+Shift+D), but faster

**Streaming Mode Details:**
- Uses `base.en` model (optimized for speed)
- 30-second audio buffer with VAD
- Types complete sentences after pauses
- No need to press keys while speaking
- Great for long-form dictation

### Waybar Indicator

The indicator shows the current mode and state:

| Icon | Mode | State | Meaning |
|------|------|-------|---------|
| 〰 | CLI | Ready | Ready to record (SUPER+Shift+D to start) |
| ● dictation | CLI | Recording | Recording your voice |
| dictation | CLI | Processing | Transcribing audio |
| ◆ | Server | Ready | Model in memory, ready to record |
| ◆ dictation | Server | Recording | Recording (faster transcription) |
| 〰 streaming | Stream | Active | Live streaming mode active (SUPER+D to stop) |

### Controls

- **SUPER+D** - Toggle live streaming mode (▶)
- **SUPER+Shift+D** - Toggle recording (CLI ● or Server ◆ mode)
- **Left-click waybar** - Same as SUPER+D (toggle streaming)
- **Right-click waybar** - Open model/mode menu
- **Hover waybar** - See current model, mode, and controls

### Which Mode Should I Use?

| Use Case | Recommended Mode | Why |
|----------|------------------|-----|
| Quick notes, commands | **CLI Mode (●)** | Low memory, good enough accuracy |
| Frequent dictation sessions | **Server Mode (◆)** | Faster, no model loading delay |
| Long-form writing, transcription | **Stream Mode (▶)** | Hands-free, natural flow |
| Professional documents | **Server Mode (◆)** with `small.en` or `medium.en` | Better accuracy, still fast |
| Maximum accuracy | **Server Mode (◆)** with `large-v3-turbo` | Best quality (~14s per transcription) |

**Memory Usage Comparison:**
- CLI mode: ~300 MB (only during transcription)
- Server mode with base.en: ~577 MB (persistent)
- Server mode with small.en: ~577 MB (persistent)  
- Server mode with large-v3-turbo: ~1.7 GB (persistent)
- Stream mode: ~300 MB (uses base.en, only while streaming)

## Configuration

### Changing the Keybinding

Edit `~/.config/sway/config`:
```bash
# Change SUPER+D to something else (e.g., SUPER+M)
bindsym $mod+m exec ~/projects/asahi-whisper-daemon/toggle_dictation.sh
```

Then reload Sway:
```bash
swaymsg reload
```

### Using a Different Model

The installer uses `base.en` by default. You can choose a different model during installation:

```bash
./install.sh --model small.en    # More accurate
./install.sh --model medium.en   # Even better accuracy
./install.sh --model large-v3    # Best accuracy, slower
```

#### Available Models

**Main English Models (Recommended):**

| Model | Size | Speed (M2) | Accuracy | Best For |
|-------|------|------------|----------|----------|
| `tiny.en` | 75 MB | ~30x realtime | Basic | Quick notes, commands |
| `base.en` | 147 MB | ~11.5x realtime | Good | **Default** - balanced |
| `small.en` | 488 MB | ~4x realtime | Better | Longer dictation |
| `medium.en` | 1.5 GB | ~2x realtime | Great | Professional work |
| `large-v3` | 3.1 GB | ~1x realtime | Best | Maximum accuracy |
| `large-v3-turbo` | 1.6 GB | ~1.5x realtime | Excellent | Faster large model |

**Notes:**
- **English-only models** (`.en`) are faster and more accurate for English than multilingual versions
- **Quantized models** (`-q5_0`, `-q5_1`, `-q8_0`) are smaller with minimal accuracy loss
- **Multilingual models** (without `.en`) support 99 languages but are slower
- **Full model list**: Run `cd ~/projects/whisper.cpp/models && ./download-ggml-model.sh` to see all available models

#### Switching Models (Interactive)

**Right-click the waybar indicator** to open the model switcher:

![Model Switcher Menu]
```
● base.en (active)      ← Currently using
✓ tiny.en              ← Downloaded
  small.en             ← Available to download
  medium.en            ← Available to download
  large-v3-turbo       ← Available to download
---
📥 Download more models...
```

- **● symbol** = Currently active model
- **✓ symbol** = Downloaded and ready to use
- **No symbol** = Available to download (will download automatically when selected)
- **Download more models...** = Opens terminal to manually download models

The daemon will automatically restart with the new model when you select one.

#### Changing Model Manually

If you prefer command-line:

```bash
cd ~/projects/whisper.cpp
./models/download-ggml-model.sh small.en

# Edit the service file
nano ~/.config/systemd/user/whisper.service

# Change the --model parameter to:
# --model /home/YOUR_USERNAME/projects/whisper.cpp/models/ggml-small.en.bin

# Reload and restart
systemctl --user daemon-reload
systemctl --user restart whisper.service
```

### Streaming Mode Requirements

Streaming mode requires SDL2 to be installed and whisper.cpp to be built with SDL2 support:

```bash
# Install SDL2
sudo dnf install SDL2 SDL2-devel

# Rebuild whisper.cpp with SDL2 support
cd ~/projects/whisper.cpp
rm -rf build
cmake -B build -DWHISPER_SDL2=ON
cmake --build build --config Release
```

After rebuilding, `whisper-stream` will be available and streaming mode will work.

### Tuning Streaming Mode

You can adjust VAD sensitivity and buffer behavior by editing `toggle_stream.sh`:

**VAD Threshold (`-vth`):**
```bash
# More sensitive (triggers on shorter pauses)
-vth 0.7

# Default (waits for natural pauses)
-vth 0.6

# Less sensitive (good for continuous speech with background noise)
-vth 0.5
```

**Buffer Settings:**
```bash
# Audio buffer length (milliseconds)
--length 30000   # Default: 30 seconds

# Buffer overlap for continuity (milliseconds)
--keep 200       # Default: 200ms overlap

# Processing threads (adjust for your CPU)
-t 8             # Default: 8 threads (good for M1/M2/M3/M4)
```

**Advanced: Deduplication Algorithm**

The streaming mode uses a character-based deduplication algorithm to prevent repeated text:

1. **Committed text tracking** - Tracks what was actually typed, not what Whisper said
2. **Character-based suffix matching** - Finds overlap using normalized text comparison
3. **Drift detection** - Detects when Whisper revises earlier text and resets state
4. **Conservative fallback** - Types only the last sentence when matching fails

This ensures clean output even during:
- Buffer shifts (when audio window moves forward)
- Whisper revisions ("gonna" → "going to", "time" → "timing")
- Word count changes that break word-based alignment
- Long pauses between thoughts

### Customizing Waybar Indicator

**Change the text/icons:**

Edit `waybar_whisper.py`:
```python
# CLI mode icon
icon = "●"

# Server mode icon  
icon = "◆"

# Stream mode icon
icon = "▶"
```

**Change colors:**

Edit `config/waybar-style.css` and apply to your `~/.config/waybar/style.css`.

### Disabling Audio Feedback

Remove or rename the sound files:
```bash
mv ~/projects/asahi-whisper-daemon/sounds ~/projects/asahi-whisper-daemon/sounds.bak
systemctl --user restart whisper.service
```

## How It Works

### CLI/Server Mode Flow

```
User presses SUPER+Shift+D
    ↓
Sway keybinding → toggle_dictation.sh
    ↓
Unix socket → whisper_daemon.py
    ↓
Audio recording (sounddevice) → 16kHz mono WAV
    ↓
whisper-cli (C++) → whisper.cpp model
    ↓
Transcribed text → wtype (types it)
    ↓
Waybar indicator updates
```

### Streaming Mode Flow

```
User presses SUPER+D (start)
    ↓
toggle_stream.sh starts whisper-stream
    ↓
Continuous audio capture with SDL2
    ↓
Voice Activity Detection (VAD) detects speech/silence
    ↓
On silence: transcribe last N seconds
    ↓
Parse output → Smart deduplication algorithm
    ↓
wtype types only NEW text
    ↓
Loop (until SUPER+D to stop)
```

### Architecture Components

**Core Services:**
- **whisper_daemon.py** - Main daemon (CLI/Server modes)
  - Runs as systemd user service
  - Handles audio recording via sounddevice
  - Manages whisper-cli subprocess
  - Server mode keeps model in memory
  
- **toggle_stream.sh** - Streaming mode controller
  - Spawns whisper-stream subprocess
  - Implements smart deduplication algorithm
  - Handles VAD output parsing
  - Auto-resets context on long silence

**IPC & State:**
- **Unix socket** - `/tmp/whisper_daemon.sock` (CLI/Server communication)
- **Flag files** - `/tmp/whisper_recording`, `/tmp/whisper_streaming`
- **Log files** - `/tmp/whisper_daemon.log`, `/tmp/whisper_stream.log`
- **Debug logs** - `/tmp/whisper_stream_debug.log` (streaming deduplication)

**Audio Pipeline:**
- **Input**: Default microphone (PipeWire/ALSA)
- **Format**: 16kHz mono WAV
- **Capture**: sounddevice (Python) for CLI/Server, SDL2 for streaming
- **Processing**: whisper.cpp with ARM optimizations

**Output:**
- **Text injection**: wtype (Wayland native)
- **Works in**: Any text field (terminal, browser, editor, etc.)
- **No clipboard pollution**: Direct keyboard input simulation

### Smart Deduplication Algorithm (Streaming Mode)

The streaming mode includes a character-based deduplication system to handle whisper.cpp's rolling buffer:

**Problem**: whisper-stream uses a 30-second sliding window. Each transcription includes previous content plus new speech. Additionally, Whisper frequently revises earlier text ("gonna" → "going to"), which breaks word-based alignment.

**Solution**: Character-based committed text tracking:

1. **Track What We Typed (Not What Whisper Said)**
   ```
   Committed: "Hello world"
   Current:   "Hello world this is new"
   Result:    Types only "this is new" ✓
   ```

2. **Character-Based Suffix Matching**
   ```
   Committed: "I'm gonna tell you a story"
   Current:   "I'm going to tell you a story about yesterday"
   Algorithm: Normalize text, find longest suffix overlap
   Result:    Types only "about yesterday" ✓
   ```
   
   Unlike word-based matching, this handles word count changes gracefully.

3. **Drift Detection & Reset**
   ```
   When Whisper revises text significantly:
   - Track consecutive matching failures
   - After 2 failures, reset committed_text to current state
   - Prevents cascading errors from stale state
   ```

4. **Conservative Fallback**
   ```
   When no overlap found:
   - Type only the last sentence (not everything)
   - Minimizes duplication on edge cases
   ```

**Memory Management:**
- Committed text trimmed to last 500 characters
- Prevents unbounded memory growth in long sessions
- Maintains enough context for accurate matching

**Edge Cases Handled:**
- Word count changes ("gonna" → "going to", "wanna" → "want to")
- Whisper's text revisions mid-stream
- Punctuation and capitalization changes
- Buffer shifts during long dictation
- Pauses that cause Whisper to re-interpret earlier speech

## Performance

### Resource Usage

**Always-On Streaming Mode** (base.en model on Apple M2):
- **Memory**: ~300 MB (persistent while streaming is active)
- **CPU**: 45% of one core during active transcription, <1% during silence
- **Battery Impact**: Minimal - only processes audio during speech (VAD)
- **Safe to leave on**: Yes! Automatically handles long sessions with silence detection

**CLI/Server Mode:**
- **Memory**: ~300 MB during transcription, 0 MB when idle (CLI), or ~577 MB persistent (Server)
- **CPU**: Only active during recording/transcription
- **Latency**: 1-2 seconds for 5-15 second clips

### Benchmarks (Apple M2, base.en model)

- **Speed**: 11.5x faster than real-time
- **Transcription time**: ~1-2 seconds for typical 5-15 second recordings
- **Model load time**: ~50ms (negligible in streaming/server mode)
- **CPU optimizations**: ARM NEON, FP16, DOTPROD acceleration

### Model Performance Comparison

| Model | Size | Speed | Accuracy | Memory (Stream) | Memory (Server) |
|-------|------|-------|----------|-----------------|-----------------|
| tiny.en | 75 MB | 30x realtime | Basic | ~100 MB | ~200 MB |
| base.en | 147 MB | 11.5x realtime | Good | ~300 MB | ~577 MB |
| small.en | 466 MB | 4x realtime | Better | ~500 MB | ~577 MB |
| large-v3-turbo | 1.6 GB | 1.5x realtime | Excellent | ~1.7 GB | ~1.7 GB |
| large-v3 | 2.9 GB | 1x realtime | Best | ~3 GB | ~3 GB |

### Long Session Support

**Streaming mode is designed for extended use:**
- ✅ **Automatic context reset** after 10+ seconds of silence
- ✅ **Intelligent deduplication** prevents repeated text
- ✅ **Fuzzy punctuation matching** handles whisper's self-corrections
- ✅ **Buffer management** handles hours of continuous dictation
- ✅ **No memory leaks** - tested for multi-hour sessions

**Can I leave streaming on all the time?**
Yes! The streaming mode only uses CPU/resources when you're actually speaking. During silence:
- VAD (Voice Activity Detection) waits for speech
- CPU usage drops to <1%
- Memory stays constant at ~300 MB
- No performance impact on other applications

## Management

### Service Commands

```bash
# Check status
systemctl --user status whisper.service

# Restart daemon
systemctl --user restart whisper.service

# Stop daemon
systemctl --user stop whisper.service

# View logs
tail -f /tmp/whisper_daemon.log

# Or systemd logs
journalctl --user -u whisper.service -f
```

### Testing Connection

```bash
# Check if daemon is responsive
echo "STATUS" | ncat -U /tmp/whisper_daemon.sock

# Should return: READY or RECORDING
```

## Troubleshooting

### Text doesn't appear

**Problem**: Recording works but no text is typed.

**Solutions:**
1. Ensure cursor is in a text field
2. Check wtype is installed: `which wtype`
3. Check logs: `tail -f /tmp/whisper_daemon.log`
4. Look for transcription output in logs

### Waybar indicator shows ● (error state)

**Problem**: Daemon isn't running.

**Solutions:**
1. Start the service: `systemctl --user start whisper.service`
2. Check status: `systemctl --user status whisper.service`
3. View errors: `journalctl --user -u whisper.service -n 50`

### SUPER+D doesn't work

**Problem**: Keybinding not responding.

**Solutions:**
1. Reload Sway: `swaymsg reload`
2. Check keybinding exists: `grep whisper ~/.config/sway/config`
3. Try running toggle script manually: `~/projects/asahi-whisper-daemon/toggle_dictation.sh`

### No sound feedback

**Problem**: No audio plays on start/stop.

**Solutions:**
1. Check sound files exist: `ls ~/projects/asahi-whisper-daemon/sounds/`
2. Test audio: `paplay ~/projects/asahi-whisper-daemon/sounds/snare.wav`
3. Check system volume isn't muted

### Slow transcription

**Problem**: Takes too long to process.

**Solutions:**
1. This is normal for first transcription (~2s as model loads)
2. Subsequent transcriptions should be ~1s
3. Using large models will be slower
4. Keep recordings under 15 seconds for best speed

### Streaming mode not deduplicating properly

**Problem**: Text is being repeated or cut off in streaming mode.

**Solutions:**
1. Check debug log: `tail -f /tmp/whisper_stream_debug.log`
2. Look for `[DEBUG] Found overlap` - this means deduplication is working
3. Look for `[DEBUG] Found committed suffix` - secondary matching worked
4. Look for `[DEBUG] Resetting committed_text due to drift` - drift detection triggered (normal)
5. Restart streaming mode: Press SUPER+D twice (off/on)

**Debug example (working correctly):**
```
[DEBUG] current_full_text: 'Hello world this is new'
[DEBUG] committed_text: 'Hello world'
[DEBUG] Found overlap (cut=0, suffix_len=11, ratio_pos=11) -> new: 'this is new'
[DEBUG] Typing: 'this is new '
[DEBUG] wtype succeeded
```

**Debug example (drift detection working):**
```
[DEBUG] No overlap found (fallback_count=2)
[DEBUG] Resetting committed_text due to drift
[DEBUG] Fallback new_text: 'just the last sentence.'
```

### Advanced debugging

**Enable verbose logging for streaming:**
```bash
# Watch all logs simultaneously
tail -f /tmp/whisper_stream.log /tmp/whisper_stream_debug.log /tmp/whisper_stream_output.log

# Or in separate terminals:
tail -f /tmp/whisper_stream.log           # whisper-stream stderr (model loading, VAD events)
tail -f /tmp/whisper_stream_output.log    # Raw whisper output (transcription blocks)
tail -f /tmp/whisper_stream_debug.log     # Our deduplication algorithm debug
```

**Inspect the deduplication algorithm:**
```bash
# See what text is being captured and matched
grep "Extracted text" /tmp/whisper_stream_debug.log

# See deduplication decisions
grep "overlap" /tmp/whisper_stream_debug.log

# See what's being typed
grep "Typing:" /tmp/whisper_stream_debug.log
```

For more detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Frequently Asked Questions

### Can I leave streaming mode on all the time?

**Yes!** Streaming mode is designed for always-on use:
- Only uses CPU when you're actively speaking
- VAD waits silently when you're not talking
- Memory stays constant at ~300 MB
- Automatically resets context after 10s silence
- No performance impact on other applications
- Battery-friendly (minimal CPU during silence)

### What's the difference between the three modes?

| Aspect | Stream Mode | CLI Mode | Server Mode |
|--------|-------------|----------|-------------|
| **Startup** | Always ready | 50ms model load | Always ready |
| **Memory** | 300 MB while active | 0 MB when idle | 577 MB persistent |
| **Best for** | Long dictation | Quick notes | Frequent short recordings |
| **Deduplication** | Smart algorithm | Not needed | Not needed |
| **Activation** | SUPER+D (toggle) | SUPER+Shift+D (hold) | SUPER+Shift+D (hold) |

### How long can I speak in streaming mode?

**Indefinitely!** The system handles:
- ✅ Hours of continuous dictation
- ✅ Automatic buffer management (30s rolling window)
- ✅ Smart deduplication prevents repetition
- ✅ Auto-reset after long pauses (>10s)
- ✅ No memory leaks or slowdown

The 30-second buffer is a rolling window - older audio gets dropped automatically while new speech is captured.

### Why do I sometimes see duplicated words?

This can happen when:
1. **Whisper revises earlier text** - Changes "gonna" to "going to" or "time" to "timing"
2. **You pause mid-sentence** - VAD might transcribe partial thoughts, then revise
3. **Drift accumulation** - After several revisions, committed text diverges from Whisper's state

The drift detection system (added in v2) handles most cases by resetting state after consecutive failures. If you see consistent duplication, check `/tmp/whisper_stream_debug.log` and report an issue.

### What happens if I pause for a long time?

After **10+ seconds of silence**:
- Context automatically resets
- Next transcription starts fresh
- Prevents slowdown from comparing huge texts
- This is intentional and expected behavior

You'll see in debug log: `[DEBUG] Long silence detected (XXXXms), resetting context`

### Can I use this for transcribing meetings?

**Yes, but with caveats:**
- Works best for **your own speech** (single speaker)
- Struggles with **multiple speakers** (no speaker diarization)
- Use **Server mode with large-v3-turbo** for best accuracy
- Consider a good quality microphone
- Or use CLI mode and record segments manually

### Does it work offline?

**100% offline!** Everything runs locally:
- No internet required
- No cloud services
- Complete privacy
- Works on airplanes, remote areas, etc.

### What about punctuation?

Whisper adds punctuation automatically:
- Periods, commas, question marks
- Capitalization
- Some basic formatting
- Works best with clear, natural speech

## Tips for Best Results

**General:**
- **Speak clearly** with good enunciation
- **Minimize background noise** for better accuracy  
- **Speak at normal pace** - not too fast or slow
- **Use in quiet environments** when possible

**Streaming Mode Specific:**
- **Pause naturally** between sentences (helps VAD)
- **Wait for text** before continuing (gives system time to process)
- **Speak in phrases** rather than very long run-on sentences
- **Use long pauses** (10+s) between different topics to reset context

**CLI/Server Mode Specific:**
- **Keep recordings short** (5-15 seconds ideal)
- **Pause before/after** speaking to ensure clean audio
- **Wait for beep** before speaking (recording started)

## Contributing

Contributions welcome! Please feel free to submit issues or pull requests.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

- **whisper.cpp**: https://github.com/ggerganov/whisper.cpp
- **OpenAI Whisper**: https://github.com/openai/whisper
- **Asahi Linux**: https://asahilinux.org/

Built with inspiration from the desktop whisper-dictation-daemon setup.

## Acknowledgments

Special thanks to:
- The Asahi Linux team for making Linux on Apple Silicon possible
- The ggerganov team for whisper.cpp
- OpenAI for the Whisper model

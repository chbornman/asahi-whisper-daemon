# Asahi Whisper Daemon

Voice dictation system using whisper.cpp for Asahi Linux on Apple Silicon.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-Asahi%20Linux-blue)](https://asahilinux.org/)

## Features

- 🎤 **SUPER+D keybinding** - Toggle recording with a single key
- 📊 **Waybar integration** - Animated visual status indicator
- 🔊 **Audio feedback** - Snare sound on start, hihat on stop
- ⚡ **Fast transcription** - 11.5x faster than real-time
- 💾 **Low memory** - ~200-300 MB (vs 3GB for large models)
- 🚀 **Auto-start** - Systemd service starts on boot
- 🎯 **Optimized for M1/M2** - ARM NEON, FP16, DOTPROD instructions

## Demo

**Waybar Indicator States:**
- `●` (gray) - Ready to record
- `● dictation` (red, golden background) - Currently recording
- `dictation` (dark text, golden background) - Processing

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

### Basic Dictation

1. **Open any text field** (editor, browser, terminal, etc.)
2. **Press SUPER+D** to start recording
   - Waybar shows: `● dictation` (red, golden background)
   - Hear: snare sound (drum hit)
3. **Speak clearly**: "This is a test of the whisper dictation system"
4. **Press SUPER+D** again to stop
   - Waybar shows: `dictation` (processing)
   - Hear: hihat sound
5. **Wait ~1-2 seconds** → Text appears where your cursor is!

### Waybar Indicator

The indicator in your waybar changes to show the current state:

| Display | Color | Meaning |
|---------|-------|---------|
| ● | Gray | Ready to record |
| ● dictation | Red text, gold bg | Recording your voice |
| dictation | Dark text, gold bg | Processing transcription |
| ● | Gray (faded) | Error - daemon not running |

### Controls

- **SUPER+D** - Toggle recording (start/stop)
- **Left-click waybar indicator** - Toggle recording
- **Right-click waybar indicator** - Switch models
- **Hover waybar indicator** - See current model and status

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

### Customizing Waybar Indicator

**Change the text/icons:**

Edit `waybar_whisper.py`:
```python
ICONS = {
    "ready": "MIC",           # Change from ●
    "recording": "REC",       # Change from ● dictation
    "processing": "...",      # Change from dictation
    "error": "ERR"
}
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

```
User presses SUPER+D
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

**Architecture:**
- **Daemon** - Python service running persistently
- **IPC** - Unix socket (`/tmp/whisper_daemon.sock`)
- **Model** - whisper.cpp base.en (kept in memory)
- **Audio** - sounddevice captures from microphone
- **Output** - wtype injects text via Wayland

## Performance

**Benchmarks** (Apple M2, base.en model):
- **Speed**: 11.5x faster than real-time
- **Memory**: 200-300 MB
- **Latency**: 1-2 seconds for 5-15 second clips
- **CPU**: Optimized with ARM NEON, FP16, DOTPROD

**Model Comparison:**

| Model | Size | Speed | Accuracy | Memory |
|-------|------|-------|----------|--------|
| tiny.en | 75 MB | Fastest | Basic | ~100 MB |
| base.en | 147 MB | Fast | Good | ~200 MB |
| small.en | 466 MB | Medium | Better | ~500 MB |
| large-v3 | 2.9 GB | Slow | Best | ~3 GB |

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

For more detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Tips for Best Results

- **Speak clearly** with good enunciation
- **Minimize background noise** for better accuracy  
- **Keep recordings short** (5-15 seconds ideal)
- **Pause before/after** speaking to help Voice Activity Detection
- **Use in quiet environments** when possible
- **Speak at normal pace** - not too fast or slow

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

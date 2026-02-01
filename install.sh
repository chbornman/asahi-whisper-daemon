#!/usr/bin/env bash
# install.sh - Install whisper dictation daemon for Asahi Linux
# MIT License - See LICENSE file

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default paths
WHISPER_CPP_DIR="$HOME/projects/whisper.cpp"
DAEMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_NAME="base.en"
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --whisper-dir)
            WHISPER_CPP_DIR="$2"
            shift 2
            ;;
        --model)
            MODEL_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run          Show what would be done without making changes"
            echo "  --whisper-dir DIR  whisper.cpp installation directory (default: ~/projects/whisper.cpp)"
            echo "  --model NAME       Whisper model to download (default: base.en)"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would run: $*"
    else
        "$@"
    fi
}

# Check if running on Asahi Linux
check_asahi() {
    log_info "Checking if running on Asahi Linux..."
    
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot detect OS - /etc/os-release not found"
        return 1
    fi
    
    if grep -qi "asahi" /etc/os-release; then
        log_success "Running on Asahi Linux"
        return 0
    else
        log_warn "Not detected as Asahi Linux - this script is designed for Asahi Linux on Apple Silicon"
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled"
            exit 0
        fi
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=()
    
    # Required commands
    local required_cmds=("swaymsg" "wtype" "parecord" "ffmpeg" "git" "cmake" "gcc" "uv")
    
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    # Check for waybar
    if ! command -v waybar &> /dev/null; then
        log_warn "waybar not found - status indicator will not work"
    fi
    
    # Check for pw-play (pipewire)
    if ! command -v pw-play &> /dev/null; then
        log_warn "pw-play not found - audio feedback will not work"
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing[*]}"
        echo ""
        echo "Install them with:"
        echo "  sudo pacman -S sway wtype pipewire-pulse ffmpeg git cmake gcc uv"
        return 1
    fi
    
    log_success "All required dependencies found"
}

# Clone and build whisper.cpp
setup_whisper_cpp() {
    log_info "Setting up whisper.cpp in $WHISPER_CPP_DIR..."
    
    if [ -d "$WHISPER_CPP_DIR" ]; then
        log_warn "whisper.cpp directory already exists at $WHISPER_CPP_DIR"
        if [ -f "$WHISPER_CPP_DIR/build/bin/whisper-cli" ]; then
            log_success "whisper.cpp binary already built"
            return 0
        else
            log_info "Binary not found, will build..."
        fi
    else
        log_info "Cloning whisper.cpp..."
        run_cmd mkdir -p "$(dirname "$WHISPER_CPP_DIR")"
        run_cmd git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_CPP_DIR"
    fi
    
    log_info "Building whisper.cpp with Metal support for Apple Silicon..."
    if [ "$DRY_RUN" = false ]; then
        cd "$WHISPER_CPP_DIR"
        make clean 2>/dev/null || true
        make -j$(nproc)
        cd "$DAEMON_DIR"
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} Would build whisper.cpp with: cd $WHISPER_CPP_DIR && make clean && make -j\$(nproc)"
    fi
    
    log_success "whisper.cpp built successfully"
}

# Download whisper model
download_model() {
    log_info "Downloading whisper model: $MODEL_NAME..."
    
    local model_file="$WHISPER_CPP_DIR/models/ggml-$MODEL_NAME.bin"
    
    if [ -f "$model_file" ]; then
        log_success "Model already downloaded: $model_file"
        return 0
    fi
    
    if [ "$DRY_RUN" = false ]; then
        cd "$WHISPER_CPP_DIR"
        bash ./models/download-ggml-model.sh "$MODEL_NAME"
        cd "$DAEMON_DIR"
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} Would download model with: cd $WHISPER_CPP_DIR && bash ./models/download-ggml-model.sh $MODEL_NAME"
    fi
    
    log_success "Model downloaded successfully"
}

# Setup Python environment
setup_python_env() {
    log_info "Setting up Python environment with uv..."
    
    if [ -d "$DAEMON_DIR/.venv" ]; then
        log_warn "Virtual environment already exists"
    else
        run_cmd uv venv "$DAEMON_DIR/.venv"
    fi
    
    log_info "Installing Python dependencies..."
    run_cmd uv pip install -r "$DAEMON_DIR/requirements.txt"
    
    log_success "Python environment ready"
}

# Install systemd service
install_systemd_service() {
    log_info "Installing systemd user service..."
    
    local service_dir="$HOME/.config/systemd/user"
    run_cmd mkdir -p "$service_dir"
    
    # Generate service file with correct paths
    local service_file="$service_dir/whisper.service"
    
    if [ "$DRY_RUN" = false ]; then
        cat > "$service_file" <<EOF
[Unit]
Description=Whisper Dictation Daemon
After=graphical-session.target

[Service]
Type=simple
WorkingDirectory=$DAEMON_DIR
ExecStart=$DAEMON_DIR/.venv/bin/python $DAEMON_DIR/whisper_daemon.py --model $WHISPER_CPP_DIR/models/ggml-$MODEL_NAME.bin --whisper-cli $WHISPER_CPP_DIR/build/bin/whisper-cli
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
        log_success "Service file created: $service_file"
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} Would create service file: $service_file"
    fi
    
    # Reload systemd
    run_cmd systemctl --user daemon-reload
    
    # Enable and start service
    run_cmd systemctl --user enable whisper.service
    run_cmd systemctl --user start whisper.service
    
    log_success "Systemd service installed and started"
}

# Update Sway config
update_sway_config() {
    log_info "Updating Sway configuration..."
    
    local sway_config="$HOME/.config/sway/config"
    
    if [ ! -f "$sway_config" ]; then
        log_warn "Sway config not found at $sway_config - skipping keybinding setup"
        echo "You'll need to manually add the keybinding. See config/sway-keybind.conf"
        return 0
    fi
    
    # Check if keybinding already exists
    if grep -q "toggle_dictation.sh" "$sway_config"; then
        log_warn "Dictation keybinding already exists in Sway config"
        return 0
    fi
    
    # Backup config
    run_cmd cp "$sway_config" "$sway_config.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Add keybinding
    local keybind="bindsym Mod4+d exec $DAEMON_DIR/toggle_dictation.sh"
    
    if [ "$DRY_RUN" = false ]; then
        echo "" >> "$sway_config"
        echo "# Whisper dictation" >> "$sway_config"
        echo "$keybind" >> "$sway_config"
        log_success "Added keybinding to Sway config"
    else
        echo -e "${YELLOW}[DRY-RUN]${NC} Would add to $sway_config: $keybind"
    fi
    
    # Reload Sway
    run_cmd swaymsg reload
}

# Update Waybar config
update_waybar_config() {
    log_info "Updating Waybar configuration..."
    
    local waybar_config="$HOME/.config/waybar/config"
    local waybar_style="$HOME/.config/waybar/style.css"
    
    if [ ! -f "$waybar_config" ]; then
        log_warn "Waybar config not found - skipping waybar setup"
        echo "See config/waybar-module.jsonc and config/waybar-style.css for manual setup"
        return 0
    fi
    
    # Check if module already exists
    if grep -q "custom/whisper" "$waybar_config"; then
        log_warn "Whisper module already exists in Waybar config"
    else
        log_warn "Please manually add the Waybar module"
        echo "See $DAEMON_DIR/config/waybar-module.jsonc for the configuration"
        echo "Add it to your Waybar config and update the exec path to: $DAEMON_DIR/waybar_whisper.py"
    fi
    
    if [ -f "$waybar_style" ]; then
        if grep -q "#custom-whisper" "$waybar_style"; then
            log_warn "Whisper styles already exist in Waybar CSS"
        else
            log_warn "Please manually add the Waybar styles"
            echo "See $DAEMON_DIR/config/waybar-style.css for the CSS"
        fi
    fi
}

# Test installation
test_installation() {
    log_info "Testing installation..."
    
    # Check if service is running
    if systemctl --user is-active --quiet whisper.service; then
        log_success "Whisper daemon is running"
    else
        log_error "Whisper daemon is not running"
        echo "Check logs with: journalctl --user -u whisper.service -n 50"
        return 1
    fi
    
    # Check if toggle script works
    if [ -x "$DAEMON_DIR/toggle_dictation.sh" ]; then
        log_success "Toggle script is executable"
    else
        log_warn "Toggle script is not executable"
        run_cmd chmod +x "$DAEMON_DIR/toggle_dictation.sh"
    fi
    
    log_success "Installation test passed"
}

# Main installation flow
main() {
    echo ""
    echo "=========================================="
    echo "  Whisper Dictation Daemon Installer"
    echo "=========================================="
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    check_asahi
    check_prerequisites
    setup_whisper_cpp
    download_model
    setup_python_env
    install_systemd_service
    update_sway_config
    update_waybar_config
    
    if [ "$DRY_RUN" = false ]; then
        test_installation
    fi
    
    echo ""
    echo "=========================================="
    log_success "Installation complete!"
    echo "=========================================="
    echo ""
    echo "Usage:"
    echo "  - Press SUPER+D to start/stop dictation"
    echo "  - Check service status: systemctl --user status whisper.service"
    echo "  - View logs: journalctl --user -u whisper.service -f"
    echo ""
    echo "Troubleshooting:"
    echo "  - If waybar module doesn't appear, manually add the configuration"
    echo "    from $DAEMON_DIR/config/waybar-module.jsonc"
    echo "  - Make sure your waybar config includes 'custom/whisper' in the modules list"
    echo ""
}

# Run main installation
main

#!/usr/bin/env python3
"""
Whisper Daemon - Persistent model with Unix socket IPC
Simpler version inspired by margo's whisper-dictation-daemon
"""
import argparse
import logging
import os
import queue
import signal
import socket
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

import numpy as np
import scipy.io.wavfile as wavfile
import sounddevice as sd

# Configuration
SOCKET_PATH = "/tmp/whisper_daemon.sock"
RECORDING_FLAG = "/tmp/whisper_recording"
SAMPLE_RATE = 16000
CHANNELS = 1

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("/tmp/whisper_daemon.log", mode="a"),
    ],
)
logger = logging.getLogger(__name__)


class WhisperDaemon:
    def __init__(self, model_path, whisper_cli_path, sound_dir=None, notifications=True):
        self.model_path = Path(model_path)
        self.whisper_cli = Path(whisper_cli_path)
        self.sound_dir = Path(sound_dir) if sound_dir else Path(__file__).parent / "sounds"
        self.notifications = notifications
        
        # State
        self.recording = False
        self.interrupted = False
        self.audio_queue = queue.Queue()
        self.server_socket = None
        
        # Audio feedback
        self.start_sound = None
        self.stop_sound = None
        self.preload_sounds()
        
        # Signal handling
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)
        
        logger.info("Whisper daemon initialized")
        logger.info(f"Model: {self.model_path}")
        logger.info(f"Whisper CLI: {self.whisper_cli}")
    
    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        logger.info("Received shutdown signal")
        self.interrupted = True
        if self.server_socket:
            self.server_socket.close()
        sys.exit(0)
    
    def preload_sounds(self):
        """Preload audio feedback sounds into memory"""
        try:
            start_file = self.sound_dir / "snare.wav"
            stop_file = self.sound_dir / "hihat.wav"
            
            if start_file.exists():
                _, self.start_sound = wavfile.read(start_file)
                logger.info(f"Loaded start sound: {start_file}")
            
            if stop_file.exists():
                _, self.stop_sound = wavfile.read(stop_file)
                logger.info(f"Loaded stop sound: {stop_file}")
        except Exception as e:
            logger.warning(f"Could not load sounds: {e}")
    
    def play_sound(self, sound_data):
        """Play audio feedback"""
        if sound_data is not None:
            try:
                sd.play(sound_data, 44100)  # Sounds are usually 44.1kHz
                sd.wait()  # Wait for sound to finish playing
            except Exception as e:
                logger.warning(f"Could not play sound: {e}")
    
    def notify(self, message, urgency="normal"):
        """Show desktop notification"""
        if not self.notifications:
            return
        try:
            subprocess.run(
                ["notify-send", "-u", urgency, "🎤 Whisper", message, "-t", "2000"],
                timeout=1
            )
        except Exception as e:
            logger.warning(f"Could not show notification: {e}")
    
    def start_recording(self):
        """Start audio recording"""
        if self.recording:
            logger.warning("Already recording")
            return "ALREADY_RECORDING"
        
        self.recording = True
        Path(RECORDING_FLAG).touch()
        
        # Play start sound
        self.play_sound(self.start_sound)
        
        # Show notification
        self.notify("Recording started... Press SUPER+D to stop")
        
        # Start recording thread
        threading.Thread(target=self._record_audio, daemon=True).start()
        
        logger.info("Recording started")
        return "RECORDING"
    
    def stop_recording(self):
        """Stop audio recording"""
        if not self.recording:
            logger.warning("Not recording")
            return "NOT_RECORDING"
        
        self.recording = False
        Path(RECORDING_FLAG).unlink(missing_ok=True)
        
        # Play stop sound
        self.play_sound(self.stop_sound)
        
        # Show notification
        self.notify("Recording stopped - transcribing...")
        
        logger.info("Recording stopped")
        return "STOPPED"
    
    def _record_audio(self):
        """Record audio in background thread"""
        logger.info("Recording thread started")
        recorded_chunks = []
        
        def audio_callback(indata, frames, time, status):
            if status:
                logger.warning(f"Audio callback status: {status}")
            if self.recording:
                recorded_chunks.append(indata.copy())
        
        # Start recording
        with sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            callback=audio_callback,
            dtype='int16'
        ):
            # Keep recording until stopped
            while self.recording:
                sd.sleep(100)
        
        # Process recorded audio
        if recorded_chunks:
            audio_data = np.concatenate(recorded_chunks, axis=0)
            self._transcribe_and_type(audio_data)
        else:
            logger.warning("No audio recorded")
    
    def _transcribe_and_type(self, audio_data):
        """Transcribe audio and type the result"""
        logger.info(f"Transcribing {len(audio_data)/SAMPLE_RATE:.1f}s of audio")
        
        # Save to temp file
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
            temp_file = tmp.name
            wavfile.write(temp_file, SAMPLE_RATE, audio_data)
        
        try:
            # Run whisper-cli
            cmd = [
                str(self.whisper_cli),
                "-m", str(self.model_path),
                "-f", temp_file,
                "-nt",  # No timestamps
                "--no-prints",  # Minimal output
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=60
            )
            
            # Extract transcription
            if result.returncode == 0:
                lines = result.stdout.strip().split('\n')
                text_lines = [
                    line.strip() for line in lines 
                    if line.strip() 
                    and not line.startswith('whisper_')
                    and not line.startswith('system_info')
                    and not line.startswith('main:')
                ]
                
                text = ' '.join(text_lines).strip()
                
                if text:
                    logger.info(f"Transcribed: {text[:50]}...")
                    self._type_text(text)
                    self.notify(f"Typed: {text[:40]}...", urgency="low")
                else:
                    logger.warning("No speech detected")
                    self.notify("No speech detected", urgency="critical")
            else:
                logger.error(f"Transcription failed: {result.stderr}")
        
        except subprocess.TimeoutExpired:
            logger.error("Transcription timeout")
        except Exception as e:
            logger.error(f"Transcription error: {e}")
        finally:
            # Clean up
            os.unlink(temp_file)
    
    def _type_text(self, text):
        """Type text using wtype"""
        try:
            subprocess.run(['wtype', '-'], input=text, text=True, check=True, timeout=5)
            logger.info("Text typed successfully")
        except FileNotFoundError:
            logger.error("wtype not found - install it for auto-typing")
        except Exception as e:
            logger.error(f"Typing error: {e}")
    
    def handle_command(self, command):
        """Handle IPC command"""
        command = command.strip().upper()
        
        if command == "START":
            return self.start_recording()
        elif command == "STOP":
            return self.stop_recording()
        elif command == "STATUS":
            return "RECORDING" if self.recording else "READY"
        elif command == "TOGGLE":
            if self.recording:
                return self.stop_recording()
            else:
                return self.start_recording()
        else:
            return "UNKNOWN_COMMAND"
    
    def handle_client(self, client_socket):
        """Handle client connection"""
        try:
            data = client_socket.recv(1024).decode()
            response = self.handle_command(data)
            client_socket.send(response.encode())
        except Exception as e:
            logger.error(f"Client handling error: {e}")
        finally:
            client_socket.close()
    
    def start(self):
        """Start the daemon"""
        logger.info("Starting Whisper daemon...")
        
        # Remove existing socket
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)
        
        # Create Unix socket
        self.server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_socket.bind(SOCKET_PATH)
        self.server_socket.listen(5)
        
        logger.info(f"Daemon listening on {SOCKET_PATH}")
        logger.info("Ready for commands")
        
        # Main loop
        while not self.interrupted:
            try:
                client_socket, _ = self.server_socket.accept()
                # Handle in thread for non-blocking
                threading.Thread(
                    target=self.handle_client,
                    args=(client_socket,),
                    daemon=True
                ).start()
            except OSError:
                if not self.interrupted:
                    logger.error("Socket error")
                break


def main():
    parser = argparse.ArgumentParser(description="Whisper Daemon")
    parser.add_argument(
        "--model", "-m",
        default="models/ggml-base.en.bin",
        help="Path to whisper model"
    )
    parser.add_argument(
        "--whisper-cli", "-w",
        default="build/bin/whisper-cli",
        help="Path to whisper-cli binary"
    )
    parser.add_argument(
        "--sound-dir", "-s",
        help="Directory containing snare.wav and hihat.wav"
    )
    parser.add_argument(
        "--no-notifications", "-n",
        action="store_true",
        help="Disable desktop notifications (use with waybar)"
    )
    
    args = parser.parse_args()
    
    # Resolve paths
    script_dir = Path(__file__).parent
    model_path = script_dir / args.model
    whisper_cli = script_dir / args.whisper_cli
    
    if not model_path.exists():
        logger.error(f"Model not found: {model_path}")
        sys.exit(1)
    
    if not whisper_cli.exists():
        logger.error(f"Whisper CLI not found: {whisper_cli}")
        sys.exit(1)
    
    # Start daemon
    daemon = WhisperDaemon(
        model_path=model_path,
        whisper_cli_path=whisper_cli,
        sound_dir=args.sound_dir,
        notifications=not args.no_notifications
    )
    daemon.start()


if __name__ == "__main__":
    main()

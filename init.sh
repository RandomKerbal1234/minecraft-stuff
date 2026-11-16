#!/bin/bash

# --- CONFIGURATION ---
SESSION_NAME="mc_server"
HDD_DIR="/home/yourusername/minecraft_hdd"      # Permanent storage on your HDD/SSD
RAM_DIR="/mnt/mc_ramdisk"                       # Mount point for the 8GB RAM disk
RAM_SIZE="8G"                                   # Maximum RAM disk size
JAVA_CMD="java -Xms4G -Xmx4G -jar server.jar nogui"
BACKUP_INTERVAL=300                             # 300 seconds = 5 minutes

# Prevent launching duplicate sessions
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Error: tmux session '$SESSION_NAME' is already running."
    echo "Attach to it using: tmux attach -t $SESSION_NAME"
    exit 1
fi

# --- 1. PREPARE AND MOUNT RAM DISK ---
echo "Preparing 8GB RAM disk at $RAM_DIR..."
sudo mkdir -p "$RAM_DIR"

if ! mountpoint -q "$RAM_DIR"; then
    sudo mount -t tmpfs -o size=$RAM_SIZE tmpfs "$RAM_DIR"
    sudo chown -R $(whoami):$(whoami) "$RAM_DIR"
fi

# --- 2. COPY SERVER TO RAM DISK ---
echo "Copying server files from HDD to RAM disk..."
rsync -av --delete "$HDD_DIR/" "$RAM_DIR/"

# --- 3. START MINECRAFT INSIDE TMUX ---
echo "Starting Minecraft server in tmux session '$SESSION_NAME'..."
tmux new-session -d -s "$SESSION_NAME" -c "$RAM_DIR" "$JAVA_CMD"

# --- 4. SAFE 5-MINUTE BACKGROUND SYNC LOOP ---
# Monitors the tmux session; exits loop automatically when Minecraft stops
while tmux has-session -t "$SESSION_NAME" 2>/dev/null; do
    sleep "$BACKUP_INTERVAL"

    # Re-check that the server is still running after sleeping
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        # Disable auto-saving and flush all chunks to the RAM disk
        tmux send-keys -t "$SESSION_NAME" "save-off" Enter
        tmux send-keys -t "$SESSION_NAME" "save-all flush" Enter
        sleep 3

        # Sync clean files to HDD
        rsync -a --delete "$RAM_DIR/" "$HDD_DIR/"

        # Re-enable auto-saving
        tmux send-keys -t "$SESSION_NAME" "save-on" Enter
    fi
done

# --- 5. FINAL SAVE AND CLEANUP ON SHUTDOWN ---
echo "Minecraft server stopped. Performing final save to HDD..."
rsync -av --delete "$RAM_DIR/" "$HDD_DIR/"

echo "Unmounting and clearing RAM disk..."
cd ~
sudo umount "$RAM_DIR"

echo "Done! World saved to $HDD_DIR and RAM disk cleared."


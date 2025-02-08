#!/bin/sh 

# Start fail2ban (如果启用了 fail2ban)
[ $X_UI_ENABLE_FAIL2BAN == "true" ] && fail2ban-client -x start

# Mount rclone love: remote storage to /mnt
rclone mount love: /mnt --allow-other --vfs-cache-mode writes &

# Run x-ui
exec /app/x-ui


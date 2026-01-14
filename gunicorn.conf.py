"""
Gunicorn configuration file for Web Kiosk Screen
"""

import os
import multiprocessing

# Bind to port 5000 (non-privileged port)
bind = "0.0.0.0:5000"

# Worker configuration
# Use eventlet for Socket.IO support
worker_class = "eventlet"
workers = 1  # Socket.IO requires single worker for proper state management

# Timeout settings
timeout = 120
keepalive = 5

# Logging
# Log to stdout/stderr for systemd to capture (journald)
# This avoids permission and directory creation issues
accesslog = "-"  # Log to stdout
errorlog = "-"   # Log to stderr
loglevel = "info"

# Process naming
proc_name = "web-kiosk-screen"

# Daemon mode (handled by systemd)
daemon = False

# Working directory
chdir = os.path.dirname(os.path.abspath(__file__))

# Graceful timeout
graceful_timeout = 30

# Maximum requests before worker restart (memory leak prevention)
max_requests = 1000
max_requests_jitter = 50

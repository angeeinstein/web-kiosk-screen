"""
Gunicorn configuration file for Web Kiosk Screen
"""

import os
import multiprocessing

# Bind to port 80 (standard HTTP port)
bind = "0.0.0.0:80"

# Worker configuration
# Use eventlet for Socket.IO support
worker_class = "eventlet"
workers = 1  # Socket.IO requires single worker for proper state management

# Timeout settings
timeout = 120
keepalive = 5

# Logging
accesslog = "/var/log/web-kiosk-screen/access.log"
errorlog = "/var/log/web-kiosk-screen/error.log"
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

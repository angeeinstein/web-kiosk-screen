# Web Kiosk Screen - Digital Signage Solution

A Python/Flask-based digital signage solution for managing and displaying content on multiple screens.

## Features

- **Multi-Screen Support**: Connect and manage multiple display screens simultaneously
- **Real-time Updates**: Changes are pushed instantly to screens via WebSocket (Socket.IO)
- **Responsive Design**: Automatically adapts to different screen sizes and resolutions
- **Offline Mode**: Screens continue showing cached content when connection is lost
- **Resilient Display**: No error messages shown to viewers - graceful degradation
- **Web Dashboard**: Full control panel for managing screens and content
- **Production Ready**: Runs with Gunicorn on port 80 as a systemd service

### Widget Types

- **Clock**: Digital clock with customizable format (12/24h) and date display
- **Weather**: Weather widget with location-based information
- **Image**: Upload and display images (PNG, JPG, GIF, WebP, SVG)
- **Website**: Embed external websites via iframe
- **Text**: Customizable text with color and font size options

## Quick Installation (Recommended)

For production deployment on Linux servers, use the automated install script:

```bash
curl -sSL https://raw.githubusercontent.com/angeeinstein/web-kiosk-screen/main/install.sh | sudo bash
```

This will:
- Install all system dependencies (Python, Git, etc.)
- Clone the repository to `/opt/web-kiosk-screen`
- Create a Python virtual environment
- Install all Python packages
- Configure and start a systemd service on port 80
- Set up log files in `/var/log/web-kiosk-screen`

After installation, access the dashboard at `http://your-server-ip/`

### Updating

To update an existing installation:

```bash
sudo /opt/web-kiosk-screen/install.sh
```

The script will detect the existing installation and offer to update it.

### Uninstalling

```bash
sudo /opt/web-kiosk-screen/install.sh --uninstall
```

## Manual Installation (Development)

### Prerequisites

- Python 3.10+
- pip (Python package manager)

### Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/angeeinstein/web-kiosk-screen.git
   cd web-kiosk-screen
   ```

2. Create a virtual environment (recommended):
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. Run the application (development mode):
   ```bash
   python app.py
   ```

5. Or run with Gunicorn (production mode):
   ```bash
   gunicorn --config gunicorn.conf.py app:app
   ```

6. Access the dashboard at `http://localhost:5000` (dev) or `http://localhost:80` (production)

## Usage

### Dashboard

1. Open the dashboard at `http://your-server-ip/dashboard`
2. Connect screens by opening `http://your-server-ip/screen` on display devices
3. Each screen gets a unique ID that can be bookmarked for persistence
4. Select a screen from the sidebar to edit its layout
5. Add widgets using the widget panel
6. Drag and resize widgets in the preview area
7. Click "Push Changes" to update the screen instantly

### Screen Display

- Open `/screen` to create a new screen with auto-generated ID
- Open `/screen/<screen_id>` to reconnect a specific screen
- Screens automatically reconnect after connection loss
- Content is cached locally and displayed during offline periods

### Service Management

When installed as a systemd service:

```bash
# View service status
sudo systemctl status web-kiosk-screen

# View logs
sudo journalctl -u web-kiosk-screen -f

# Restart service
sudo systemctl restart web-kiosk-screen

# Stop service
sudo systemctl stop web-kiosk-screen

# Start service
sudo systemctl start web-kiosk-screen
```

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/screens` | List all connected screens |
| GET | `/api/screens/<id>` | Get screen details |
| PUT | `/api/screens/<id>` | Update screen settings |
| GET | `/api/screens/<id>/layout` | Get screen layout |
| PUT | `/api/screens/<id>/layout` | Update screen layout |
| POST | `/api/upload` | Upload image file |

### WebSocket Events

**Client → Server:**
- `register_screen`: Register a new screen
- `screen_heartbeat`: Keep screen connection alive
- `push_layout`: Push layout to a screen
- `refresh_screen`: Request screen refresh

**Server → Client:**
- `layout_update`: New layout data
- `screen_status`: Screen connection status change
- `refresh`: Refresh request

## Configuration

Environment variables:
- `PORT`: Server port (default: 5000 for dev, 80 for production)
- `SECRET_KEY`: Flask secret key (auto-generated during installation)
- `FLASK_DEBUG`: Enable debug mode (true/false)

## Architecture

```
┌─────────────────┐     WebSocket      ┌──────────────────┐
│    Dashboard    │◄──────────────────►│   Flask Server   │
│   (Browser)     │                    │   (Gunicorn)     │
└─────────────────┘                    └────────┬─────────┘
                                                │
                    ┌───────────────────────────┼───────────────────────────┐
                    │                           │                           │
              ┌─────▼─────┐              ┌──────▼──────┐              ┌──────▼──────┐
              │  Screen 1  │              │  Screen 2   │              │  Screen N   │
              │ (Browser)  │              │  (Browser)  │              │  (Browser)  │
              └────────────┘              └─────────────┘              └─────────────┘
```

## Supported Operating Systems

The install script supports:
- Ubuntu / Debian
- CentOS / RHEL / Rocky Linux / AlmaLinux
- Fedora
- Arch Linux / Manjaro
- openSUSE / SLES

## License

MIT License
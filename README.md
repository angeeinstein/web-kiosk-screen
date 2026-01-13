# Web Kiosk Screen - Digital Signage Solution

A Python/Flask-based digital signage solution for managing and displaying content on multiple screens.

## Features

- **Multi-Screen Support**: Connect and manage multiple display screens simultaneously
- **Real-time Updates**: Changes are pushed instantly to screens via WebSocket (Socket.IO)
- **Responsive Design**: Automatically adapts to different screen sizes and resolutions
- **Offline Mode**: Screens continue showing cached content when connection is lost
- **Resilient Display**: No error messages shown to viewers - graceful degradation
- **Web Dashboard**: Full control panel for managing screens and content

### Widget Types

- **Clock**: Digital clock with customizable format (12/24h) and date display
- **Weather**: Weather widget with location-based information
- **Image**: Upload and display images (PNG, JPG, GIF, WebP, SVG)
- **Website**: Embed external websites via iframe
- **Text**: Customizable text with color and font size options

## Installation

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

4. Run the application:
   ```bash
   python app.py
   ```

5. Access the dashboard at `http://localhost:5000`

## Usage

### Dashboard

1. Open the dashboard at `http://localhost:5000/dashboard`
2. Connect screens by opening `http://localhost:5000/screen` on display devices
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
- `PORT`: Server port (default: 5000)
- `SECRET_KEY`: Flask secret key (change in production)
- `FLASK_DEBUG`: Enable debug mode (true/false)

## Architecture

```
┌─────────────────┐     WebSocket      ┌──────────────────┐
│    Dashboard    │◄──────────────────►│   Flask Server   │
│   (Browser)     │                    │   + Socket.IO    │
└─────────────────┘                    └────────┬─────────┘
                                                │
                    ┌───────────────────────────┼───────────────────────────┐
                    │                           │                           │
              ┌─────▼─────┐              ┌──────▼──────┐              ┌──────▼──────┐
              │  Screen 1  │              │  Screen 2   │              │  Screen N   │
              │ (Browser)  │              │  (Browser)  │              │  (Browser)  │
              └────────────┘              └─────────────┘              └─────────────┘
```

## License

MIT License
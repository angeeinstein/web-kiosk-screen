"""
Web Kiosk Screen - Digital Signage Solution
A Flask-based application for managing digital signage displays.
"""

import os
import uuid
import json
from datetime import datetime
from flask import Flask, render_template, request, jsonify, send_from_directory
from flask_socketio import SocketIO, emit, join_room, leave_room
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')
app.config['UPLOAD_FOLDER'] = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'static', 'uploads')
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024  # 16MB max file size

ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'}

socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

# In-memory storage for screens and content
screens = {}  # {screen_id: {name, last_seen, connected, sid, resolution}}
content_layouts = {}  # {screen_id: {widgets: [...]}}


def allowed_file(filename):
    """Check if file extension is allowed."""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def get_default_layout():
    """Return default layout for a new screen."""
    return {
        'widgets': [
            {
                'id': str(uuid.uuid4()),
                'type': 'clock',
                'x': 50,
                'y': 50,
                'width': 300,
                'height': 150,
                'settings': {
                    'format': '24h',
                    'showDate': True,
                    'timezone': 'local'
                }
            }
        ],
        'background': '#1a1a2e'
    }


# Routes
@app.route('/')
def index():
    """Redirect to dashboard."""
    return render_template('dashboard.html')


@app.route('/dashboard')
def dashboard():
    """Admin dashboard for managing screens."""
    return render_template('dashboard.html')


@app.route('/screen')
def screen():
    """Screen display page."""
    screen_id = request.args.get('id', str(uuid.uuid4()))
    return render_template('screen.html', screen_id=screen_id)


@app.route('/screen/<screen_id>')
def screen_with_id(screen_id):
    """Screen display page with ID in URL."""
    return render_template('screen.html', screen_id=screen_id)


# API Routes
@app.route('/api/screens', methods=['GET'])
def get_screens():
    """Get list of all screens."""
    screen_list = []
    for sid, data in screens.items():
        screen_list.append({
            'id': sid,
            'name': data.get('name', f'Screen {sid[:8]}'),
            'connected': data.get('connected', False),
            'last_seen': data.get('last_seen', ''),
            'resolution': data.get('resolution', 'Unknown')
        })
    return jsonify(screen_list)


@app.route('/api/screens/<screen_id>', methods=['GET'])
def get_screen(screen_id):
    """Get details of a specific screen."""
    if screen_id in screens:
        data = screens[screen_id]
        return jsonify({
            'id': screen_id,
            'name': data.get('name', f'Screen {screen_id[:8]}'),
            'connected': data.get('connected', False),
            'last_seen': data.get('last_seen', ''),
            'resolution': data.get('resolution', 'Unknown'),
            'layout': content_layouts.get(screen_id, get_default_layout())
        })
    return jsonify({'error': 'Screen not found'}), 404


@app.route('/api/screens/<screen_id>', methods=['PUT'])
def update_screen(screen_id):
    """Update screen settings."""
    if screen_id not in screens:
        return jsonify({'error': 'Screen not found'}), 404
    
    data = request.get_json()
    if 'name' in data:
        screens[screen_id]['name'] = data['name']
    
    return jsonify({'success': True})


@app.route('/api/screens/<screen_id>', methods=['DELETE'])
def delete_screen(screen_id):
    """Delete a screen and its layout."""
    if screen_id not in screens:
        return jsonify({'error': 'Screen not found'}), 404
    
    # Remove screen and its layout
    del screens[screen_id]
    if screen_id in content_layouts:
        del content_layouts[screen_id]
    
    # Notify dashboard
    socketio.emit('screen_deleted', {'id': screen_id}, namespace='/')
    
    return jsonify({'success': True})


@app.route('/api/screens/<screen_id>/layout', methods=['GET'])
def get_layout(screen_id):
    """Get layout for a screen."""
    layout = content_layouts.get(screen_id, get_default_layout())
    return jsonify(layout)


@app.route('/api/screens/<screen_id>/layout', methods=['PUT'])
def update_layout(screen_id):
    """Update layout for a screen."""
    data = request.get_json()
    content_layouts[screen_id] = data
    
    # Push update to screen if connected
    if screen_id in screens and screens[screen_id].get('sid'):
        socketio.emit('layout_update', data, room=screens[screen_id]['sid'])
    
    return jsonify({'success': True})


@app.route('/api/upload', methods=['POST'])
def upload_file():
    """Handle file uploads."""
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
    
    if file and allowed_file(file.filename):
        filename = secure_filename(file.filename)
        # Add unique prefix to avoid collisions
        unique_filename = f"{uuid.uuid4().hex[:8]}_{filename}"
        filepath = os.path.join(app.config['UPLOAD_FOLDER'], unique_filename)
        
        # Ensure upload directory exists
        os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
        
        file.save(filepath)
        return jsonify({
            'success': True,
            'filename': unique_filename,
            'url': f'/static/uploads/{unique_filename}'
        })
    
    return jsonify({'error': 'File type not allowed'}), 400


@app.route('/static/uploads/<filename>')
def uploaded_file(filename):
    """Serve uploaded files."""
    return send_from_directory(app.config['UPLOAD_FOLDER'], filename)


# Socket.IO Events
@socketio.on('connect')
def handle_connect():
    """Handle client connection."""
    print(f"Client connected: {request.sid}")


@socketio.on('disconnect')
def handle_disconnect():
    """Handle client disconnection."""
    print(f"Client disconnected: {request.sid}")
    # Find and mark screen as disconnected
    for screen_id, data in screens.items():
        if data.get('sid') == request.sid:
            screens[screen_id]['connected'] = False
            screens[screen_id]['last_seen'] = datetime.now().isoformat()
            # Notify dashboard
            socketio.emit('screen_status', {
                'id': screen_id,
                'connected': False,
                'last_seen': screens[screen_id]['last_seen']
            }, namespace='/')
            break


@socketio.on('register_screen')
def handle_register_screen(data):
    """Handle screen registration."""
    screen_id = data.get('screen_id', str(uuid.uuid4()))
    resolution = data.get('resolution', 'Unknown')
    
    if screen_id not in screens:
        screens[screen_id] = {
            'name': f'Screen {screen_id[:8]}',
            'connected': True,
            'last_seen': datetime.now().isoformat(),
            'sid': request.sid,
            'resolution': resolution
        }
        content_layouts[screen_id] = get_default_layout()
    else:
        screens[screen_id]['connected'] = True
        screens[screen_id]['last_seen'] = datetime.now().isoformat()
        screens[screen_id]['sid'] = request.sid
        screens[screen_id]['resolution'] = resolution
    
    join_room(request.sid)
    
    # Send current layout to screen
    layout = content_layouts.get(screen_id, get_default_layout())
    emit('layout_update', layout)
    
    # Notify dashboard
    socketio.emit('screen_status', {
        'id': screen_id,
        'name': screens[screen_id]['name'],
        'connected': True,
        'last_seen': screens[screen_id]['last_seen'],
        'resolution': resolution
    }, namespace='/')
    
    print(f"Screen registered: {screen_id}")


@socketio.on('screen_heartbeat')
def handle_heartbeat(data):
    """Handle screen heartbeat."""
    screen_id = data.get('screen_id')
    if screen_id and screen_id in screens:
        screens[screen_id]['last_seen'] = datetime.now().isoformat()
        screens[screen_id]['connected'] = True
        screens[screen_id]['sid'] = request.sid


@socketio.on('join_dashboard')
def handle_join_dashboard():
    """Handle dashboard connection."""
    join_room('dashboard')
    # Send current screen list
    emit('screens_list', list(screens.keys()))


@socketio.on('push_layout')
def handle_push_layout(data):
    """Push layout update to a specific screen."""
    screen_id = data.get('screen_id')
    layout = data.get('layout')
    
    if screen_id and layout:
        content_layouts[screen_id] = layout
        if screen_id in screens and screens[screen_id].get('sid'):
            socketio.emit('layout_update', layout, room=screens[screen_id]['sid'])
            emit('push_success', {'screen_id': screen_id})
        else:
            emit('push_error', {'screen_id': screen_id, 'error': 'Screen not connected'})


@socketio.on('refresh_screen')
def handle_refresh_screen(data):
    """Request a screen to refresh."""
    screen_id = data.get('screen_id')
    if screen_id and screen_id in screens and screens[screen_id].get('sid'):
        socketio.emit('refresh', {}, room=screens[screen_id]['sid'])


if __name__ == '__main__':
    # Ensure upload directory exists
    os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)
    
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('FLASK_DEBUG', 'false').lower() == 'true'
    
    socketio.run(app, host='0.0.0.0', port=port, debug=debug)

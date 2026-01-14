#!/bin/bash
#
# Web Kiosk Screen - Installation Script
# This script installs and configures the digital signage solution
#
# Usage: curl -sSL https://raw.githubusercontent.com/angeeinstein/web-kiosk-screen/main/install.sh | sudo bash
#   or: sudo ./install.sh
#

set -e

# Configuration
REPO_URL="https://github.com/angeeinstein/web-kiosk-screen.git"
INSTALL_DIR="/opt/web-kiosk-screen"
SERVICE_NAME="web-kiosk-screen"
LOG_DIR="/var/log/web-kiosk-screen"
BRANCH="${BRANCH:-main}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect OS and package manager
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
    else
        log_error "Unsupported operating system"
        exit 1
    fi
    
    log_info "Detected OS: $OS $OS_VERSION"
}

# Get or create service user
get_service_user() {
    # Try common web server users in order of preference
    for user in www-data nginx apache http nobody; do
        if id "$user" &>/dev/null; then
            SERVICE_USER="$user"
            SERVICE_GROUP="$user"
            log_info "Using service user: $SERVICE_USER"
            return 0
        fi
    done
    
    # Create www-data user if none found
    log_info "Creating service user www-data..."
    useradd --system --no-create-home --shell /bin/false www-data 2>/dev/null || true
    SERVICE_USER="www-data"
    SERVICE_GROUP="www-data"
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq python3 python3-venv python3-pip git curl nginx
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y python3 python3-pip git curl nginx
            else
                yum install -y python3 python3-pip git curl nginx
            fi
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm python python-pip git curl nginx
            ;;
        opensuse*|sles)
            zypper install -y python3 python3-pip git curl nginx
            ;;
        *)
            log_warn "Unknown OS, attempting to continue..."
            ;;
    esac
    
    # Verify python3 is available
    if ! command -v python3 &> /dev/null; then
        log_error "Python3 installation failed or not found"
        exit 1
    fi
    
    log_success "System dependencies installed"
}

# Generate secure secret key
generate_secret_key() {
    local secret_key=""
    
    # Try Python secrets module first
    if command -v python3 &> /dev/null; then
        secret_key=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null) || true
    fi
    
    # Fallback to /dev/urandom if Python fails
    if [[ -z "$secret_key" ]]; then
        log_warn "Python secrets module unavailable, using /dev/urandom"
        secret_key=$(head -c 32 /dev/urandom | xxd -p | tr -d '\n')
    fi
    
    # Final fallback to openssl
    if [[ -z "$secret_key" ]]; then
        log_warn "Using openssl for secret key generation"
        secret_key=$(openssl rand -hex 32 2>/dev/null) || true
    fi
    
    # Error if all methods fail
    if [[ -z "$secret_key" || ${#secret_key} -lt 32 ]]; then
        log_error "Failed to generate secure secret key"
        exit 1
    fi
    
    echo "$secret_key"
}

# Configure nginx reverse proxy
configure_nginx() {
    log_info "Configuring nginx reverse proxy..."
    
    # Check if nginx is installed
    if ! command -v nginx &> /dev/null; then
        log_error "Nginx is not installed"
        return 1
    fi
    
    # Copy nginx configuration
    if [[ -f "$INSTALL_DIR/nginx.conf" ]]; then
        # For Debian/Ubuntu (sites-available/sites-enabled pattern)
        if [[ -d /etc/nginx/sites-available ]]; then
            cp "$INSTALL_DIR/nginx.conf" "/etc/nginx/sites-available/$SERVICE_NAME"
            
            # Remove default site if it exists
            rm -f /etc/nginx/sites-enabled/default
            
            # Enable our site
            ln -sf "/etc/nginx/sites-available/$SERVICE_NAME" "/etc/nginx/sites-enabled/$SERVICE_NAME"
        # For RHEL/CentOS/Fedora (conf.d pattern)
        elif [[ -d /etc/nginx/conf.d ]]; then
            cp "$INSTALL_DIR/nginx.conf" "/etc/nginx/conf.d/$SERVICE_NAME.conf"
            
            # Disable default server if it exists
            if [[ -f /etc/nginx/conf.d/default.conf ]]; then
                mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.disabled 2>/dev/null || true
            fi
        else
            log_warn "Unknown nginx configuration directory structure"
            cp "$INSTALL_DIR/nginx.conf" "/etc/nginx/$SERVICE_NAME.conf"
        fi
        
        # Test nginx configuration
        if nginx -t 2>/dev/null; then
            # Enable and restart nginx
            systemctl enable nginx
            systemctl restart nginx
            log_success "Nginx configured and restarted successfully"
        else
            log_error "Nginx configuration test failed"
            return 1
        fi
    else
        log_warn "Nginx configuration file not found at $INSTALL_DIR/nginx.conf"
        return 1
    fi
}

# Get IP address with fallback
get_ip_address() {
    local ip=""
    
    # Try hostname -I first
    ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true
    
    # Fallback to ip command
    if [[ -z "$ip" ]]; then
        ip=$(ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1) || true
    fi
    
    # Fallback to ifconfig
    if [[ -z "$ip" ]]; then
        ip=$(ifconfig 2>/dev/null | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -1) || true
    fi
    
    # Default fallback
    if [[ -z "$ip" ]]; then
        ip="localhost"
    fi
    
    echo "$ip"
}

# Check if service is already installed
check_existing_installation() {
    if [[ -d "$INSTALL_DIR" ]] || systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Update existing installation
update_installation() {
    log_info "Existing installation detected at $INSTALL_DIR"
    
    # First, update the install script itself
    log_info "Checking for install script updates..."
    
    TEMP_SCRIPT=$(mktemp)
    if curl -sSL "${REPO_URL%.git}/raw/${BRANCH}/install.sh" -o "$TEMP_SCRIPT" 2>/dev/null; then
        # Check if the script has changed
        if [[ -f "$INSTALL_DIR/install.sh" ]]; then
            if ! diff -q "$TEMP_SCRIPT" "$INSTALL_DIR/install.sh" > /dev/null 2>&1; then
                log_info "Install script has been updated. Re-running with new version..."
                cp "$TEMP_SCRIPT" "$INSTALL_DIR/install.sh"
                chmod +x "$INSTALL_DIR/install.sh"
                rm -f "$TEMP_SCRIPT"
                exec "$INSTALL_DIR/install.sh" --update
            fi
        fi
    fi
    rm -f "$TEMP_SCRIPT"
    
    # Get service user
    get_service_user
    
    # Ensure nginx is installed (in case it wasn't before)
    log_info "Checking for nginx..."
    if ! command -v nginx &> /dev/null; then
        log_info "Nginx not found, installing..."
        case $OS in
            ubuntu|debian)
                apt-get install -y -qq nginx
                ;;
            centos|rhel|fedora|rocky|almalinux)
                if command -v dnf &> /dev/null; then
                    dnf install -y nginx
                else
                    yum install -y nginx
                fi
                ;;
            arch|manjaro)
                pacman -Sy --noconfirm nginx
                ;;
            opensuse*|sles)
                zypper install -y nginx
                ;;
        esac
    fi
    
    log_info "Stopping service..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    
    log_info "Updating from git repository..."
    cd "$INSTALL_DIR"
    
    # Stash any local changes
    git stash 2>/dev/null || true
    
    # Fetch and pull latest changes
    git fetch origin "$BRANCH"
    git checkout "$BRANCH"
    git reset --hard "origin/$BRANCH"
    
    # Update Python dependencies
    log_info "Updating Python dependencies..."
    "$INSTALL_DIR/venv/bin/pip" install --upgrade pip -q
    "$INSTALL_DIR/venv/bin/pip" install -r requirements.txt -q
    
    # Update systemd service file if changed
    if ! diff -q "$INSTALL_DIR/web-kiosk-screen.service" "/etc/systemd/system/$SERVICE_NAME.service" > /dev/null 2>&1; then
        log_info "Updating systemd service file..."
        # Preserve the existing secret key
        EXISTING_KEY=$(grep -oP '(?<=SECRET_KEY=)[^"]+' "/etc/systemd/system/$SERVICE_NAME.service" 2>/dev/null || echo "")
        if [[ -z "$EXISTING_KEY" || "$EXISTING_KEY" == "change-this-to-a-secure-random-string" ]]; then
            EXISTING_KEY=$(generate_secret_key)
        fi
        sed -e "s/change-this-to-a-secure-random-string/$EXISTING_KEY/" \
            -e "s/User=www-data/User=$SERVICE_USER/" \
            -e "s/Group=www-data/Group=$SERVICE_GROUP/" \
            "$INSTALL_DIR/web-kiosk-screen.service" > "/etc/systemd/system/$SERVICE_NAME.service"
        systemctl daemon-reload
    fi
    
    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    
    # Update nginx configuration
    configure_nginx || log_warn "Nginx configuration update failed"
    
    log_info "Starting service..."
    systemctl start "$SERVICE_NAME"
    
    log_success "Update completed successfully!"
    show_status
}

# Fresh installation
fresh_install() {
    log_info "Starting fresh installation..."
    
    # Install system dependencies
    install_dependencies
    
    # Get service user
    get_service_user
    
    # Create log directory
    log_info "Creating log directory..."
    mkdir -p "$LOG_DIR"
    chown "$SERVICE_USER:$SERVICE_GROUP" "$LOG_DIR"
    chmod 755 "$LOG_DIR"
    
    # Clone repository
    log_info "Cloning repository..."
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
    fi
    git clone -b "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    
    # Create virtual environment
    log_info "Creating Python virtual environment..."
    python3 -m venv "$INSTALL_DIR/venv"
    
    # Install Python dependencies
    log_info "Installing Python dependencies..."
    "$INSTALL_DIR/venv/bin/pip" install --upgrade pip -q
    "$INSTALL_DIR/venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt" -q
    
    # Create uploads directory
    log_info "Creating uploads directory..."
    mkdir -p "$INSTALL_DIR/static/uploads"
    
    # Set permissions
    log_info "Setting permissions..."
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    
    # Generate random secret key
    log_info "Generating secure secret key..."
    SECRET_KEY=$(generate_secret_key)
    
    # Install systemd service
    log_info "Installing systemd service..."
    sed -e "s/change-this-to-a-secure-random-string/$SECRET_KEY/" \
        -e "s/User=www-data/User=$SERVICE_USER/" \
        -e "s/Group=www-data/Group=$SERVICE_GROUP/" \
        "$INSTALL_DIR/web-kiosk-screen.service" > "/etc/systemd/system/$SERVICE_NAME.service"
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable and start service
    log_info "Enabling and starting service..."
    systemctl enable "$SERVICE_NAME"
    systemctl start "$SERVICE_NAME"
    
    # Configure nginx
    configure_nginx || log_warn "Nginx configuration failed - service is still accessible on port 5000"
    
    log_success "Installation completed successfully!"
    show_status
}

# Show service status and access info
show_status() {
    echo ""
    echo "=============================================="
    echo "   Web Kiosk Screen - Installation Complete"
    echo "=============================================="
    echo ""
    
    # Get IP address
    IP_ADDR=$(get_ip_address)
    
    echo "Service Status:"
    systemctl status "$SERVICE_NAME" --no-pager -l | head -10
    echo ""
    echo "Access URLs:"
    echo "  Dashboard: http://$IP_ADDR/"
    echo "  Screen:    http://$IP_ADDR/screen"
    echo ""
    echo "Useful Commands:"
    echo "  View logs:     journalctl -u $SERVICE_NAME -f"
    echo "  Restart:       systemctl restart $SERVICE_NAME"
    echo "  Stop:          systemctl stop $SERVICE_NAME"
    echo "  Update:        sudo $INSTALL_DIR/install.sh"
    echo ""
}

# Uninstall function
uninstall() {
    log_info "Uninstalling Web Kiosk Screen..."
    
    # Stop and disable service
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    # Remove service file
    rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    systemctl daemon-reload
    
    # Remove nginx configuration
    rm -f "/etc/nginx/sites-available/$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/nginx/sites-enabled/$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/nginx/conf.d/$SERVICE_NAME.conf" 2>/dev/null || true
    
    # Reload nginx if it's running
    if systemctl is-active --quiet nginx 2>/dev/null; then
        systemctl reload nginx 2>/dev/null || true
    fi
    
    # Remove installation directory
    rm -rf "$INSTALL_DIR"
    
    # Remove log directory
    rm -rf "$LOG_DIR"
    
    log_success "Uninstallation completed"
}

# Main function
main() {
    echo ""
    echo "=============================================="
    echo "   Web Kiosk Screen - Installation Script"
    echo "=============================================="
    echo ""
    
    check_root
    detect_os
    
    # Parse arguments
    case "${1:-}" in
        --uninstall)
            uninstall
            exit 0
            ;;
        --update)
            if check_existing_installation; then
                update_installation
            else
                log_error "No existing installation found"
                exit 1
            fi
            exit 0
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --update      Update existing installation"
            echo "  --uninstall   Remove installation"
            echo "  --help        Show this help message"
            echo ""
            exit 0
            ;;
    esac
    
    # Check for existing installation
    if check_existing_installation; then
        echo ""
        echo "An existing installation was detected."
        echo ""
        echo "Options:"
        echo "  1) Update to latest version"
        echo "  2) Reinstall (fresh install)"
        echo "  3) Uninstall"
        echo "  4) Cancel"
        echo ""
        
        # Check if running non-interactively
        if [[ ! -t 0 ]]; then
            log_info "Running non-interactively, defaulting to update..."
            update_installation
            exit 0
        fi
        
        read -p "Select option [1-4]: " choice
        
        case $choice in
            1)
                update_installation
                ;;
            2)
                uninstall
                fresh_install
                ;;
            3)
                uninstall
                ;;
            4|*)
                log_info "Installation cancelled"
                exit 0
                ;;
        esac
    else
        fresh_install
    fi
}

# Run main function
main "$@"

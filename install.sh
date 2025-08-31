#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
KRATOS_URL="https://autrik.com/api/.ory/kratos/public"
TOKEN_DIR="$HOME/.skyclient"
TOKEN_FILE="$TOKEN_DIR/token"

# Configuration URLs - update these with actual URLs
FILEBROWSER_CONFIG_URL="https://raw.githubusercontent.com/ykhedar/install/main/filebrowser.json"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/ykhedar/install/main/docker-compose.yaml"
MAVLINK_ROUTER_CONFIG_URL="https://raw.githubusercontent.com/ykhedar/install/main/mavlink-router.conf"

# Debug flag - set to 1 to enable debug output
DEBUG=${DEBUG:-0}

# Function to print colored output
print_debug() {
    if [ "$DEBUG" = "1" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if required tools are installed
check_dependencies() {
    print_debug "Checking dependencies..."
    local missing_deps=()
    
    for cmd in curl jq; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_info "Missing dependencies detected: ${missing_deps[*]}"
        print_info "Would you like to install missing dependencies? (y/n)"
        read -r install_deps
        
        if [[ "$install_deps" =~ ^[Yy]$ ]]; then
            install_dependencies "${missing_deps[@]}"
        else
            print_error "Required dependencies are missing. Please install: ${missing_deps[*]}"
            exit 1
        fi
    fi
    
    print_debug "Dependencies checked successfully"
}

# Function to install missing dependencies using apt-get
install_dependencies() {
    local deps_to_install=("$@")
    print_info "Installing dependencies: ${deps_to_install[*]}"
    
    print_info "Updating package list and installing dependencies..."
    apt-get update && apt-get install -y "${deps_to_install[@]}"
    
    if [ $? -eq 0 ]; then
        print_success "Dependencies installed successfully"
    else
        print_error "Failed to install dependencies"
        exit 1
    fi
    
    # Verify installation
    for cmd in "${deps_to_install[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            print_error "Failed to install $cmd"
            exit 1
        fi
    done
}

# Function to install development environment (optional)
install_dev_environment() {
    print_info "Installing development environment..."
    
    print_info "[1/8] Updating package list and installing basic tools..."
    apt-get update && apt-get install -y git wget curl nano net-tools
    if [ $? -eq 0 ]; then
        print_success "Basic tools installed successfully"
    else
        print_error "Failed to install basic tools"
        exit 1
    fi
    
    print_info "[2/8] Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    if [ $? -eq 0 ]; then
        print_success "Docker installed successfully"
    else
        print_error "Failed to install Docker"
        exit 1
    fi
    
    print_info "[3/8] Installing code-server..."
    curl -fsSL https://code-server.dev/install.sh | sh
    if [ $? -eq 0 ]; then
        print_success "code-server installed successfully"
    else
        print_error "Failed to install code-server"
        exit 1
    fi
    
    print_info "[4/8] Enabling and starting code-server service..."
    systemctl enable --now code-server@$USER
    if [ $? -eq 0 ]; then
        print_success "code-server service enabled and started"
    else
        print_error "Failed to enable code-server service"
        exit 1
    fi
    
    print_info "[5/8] Creating code-server configuration..."
    mkdir -p ~/.config/code-server
    cat << EOF > ~/.config/code-server/config.yaml
bind-addr: 0.0.0.0:8085
auth: password
password: asdf
cert: false
EOF
    if [ $? -eq 0 ]; then
        print_success "Configuration file created at ~/.config/code-server/config.yaml"
    else
        print_error "Failed to create configuration file"
        exit 1
    fi
    
    print_info "[6/8] Restarting code-server service with new configuration..."
    systemctl restart code-server@$USER
    if [ $? -eq 0 ]; then
        print_success "code-server service restarted successfully"
    else
        print_error "Failed to restart code-server service"
        exit 1
    fi
    
    print_info "[7/8] Checking code-server status..."
    systemctl status code-server@$USER --no-pager
    
    print_info "[8/8] Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    if [ $? -eq 0 ]; then
        print_success "Tailscale installed successfully"
    else
        print_error "Failed to install Tailscale"
        exit 1
    fi
    
    print_success "========================================="
    print_success "Development environment setup completed!"
    print_success "========================================="
    print_info "Next steps:"
    print_info "• code-server is running on port 8085"
    print_info "• Login password: asdf"
    print_info "• To use Docker, you may need to log out and back in"
    print_info "• To connect Tailscale, run: tailscale up"
    print_success "========================================="
}

# Function to create required directories
create_directories() {
    print_info "Creating required directories..."
    
    local directories=(
        "$HOME/.skyclient"
        "$HOME/.skyclient/filebrowser/config"
        "$HOME/.skyclient/filebrowser/database"
        "$HOME/autrikos"
    )
    
    for dir in "${directories[@]}"; do
        if [ ! -d "$dir" ]; then
            print_debug "Creating directory: $dir"
            mkdir -p "$dir"
            if [ $? -eq 0 ]; then
                print_debug "✓ Created $dir"
            else
                print_error "✗ Failed to create $dir"
                exit 1
            fi
        else
            print_debug "Directory already exists: $dir"
        fi
    done
    
    print_success "Directory structure created successfully"
}

# Function to download configuration files
download_config_files() {
    print_info "Downloading configuration files..."
    
    # Download filebrowser settings.json
    print_debug "Downloading filebrowser settings..."
    local filebrowser_config="$HOME/.skyclient/filebrowser/config/settings.json"
    if curl -fsSL "$FILEBROWSER_CONFIG_URL" -o "$filebrowser_config" 2>/dev/null; then
        print_debug "✓ Downloaded filebrowser settings.json"
    else
        print_error "✗ Failed to download filebrowser settings from $FILEBROWSER_CONFIG_URL"
        print_info "Creating default filebrowser settings..."
        create_default_filebrowser_config "$filebrowser_config"
    fi
    
    # Download docker-compose.yaml
    print_debug "Downloading docker-compose.yaml..."
    local docker_compose="$HOME/.skyclient/docker-compose.yaml"
    if curl -fsSL "$DOCKER_COMPOSE_URL" -o "$docker_compose" 2>/dev/null; then
        print_debug "✓ Downloaded docker-compose.yaml"
    else
        print_error "✗ Failed to download docker-compose.yaml from $DOCKER_COMPOSE_URL"
        print_info "Creating default docker-compose.yaml..."
        create_default_docker_compose "$docker_compose"
    fi
    
    # Download mavlink-router.conf
    print_debug "Downloading mavlink-router.conf..."
    local mavlink_config="$HOME/.skyclient/mavlink-router.conf"
    if curl -fsSL "$MAVLINK_ROUTER_CONFIG_URL" -o "$mavlink_config" 2>/dev/null; then
        print_debug "✓ Downloaded mavlink-router.conf"
    else
        print_error "✗ Failed to download mavlink-router.conf from $MAVLINK_ROUTER_CONFIG_URL"
        print_info "Creating default mavlink-router.conf..."
        create_default_mavlink_config "$mavlink_config"
    fi
    
    print_success "Configuration files setup completed"
}

# Function to create default filebrowser config if download fails
create_default_filebrowser_config() {
    local config_file="$1"
    cat << 'EOF' > "$config_file"
{
  "port": 8080,
  "baseURL": "",
  "address": "",
  "log": "stdout",
  "database": "/database/filebrowser.db",
  "root": "/srv",
  "username": "admin",
  "password": "admin"
}
EOF
    print_debug "✓ Created default filebrowser settings.json"
}

# Function to create default docker-compose if download fails
create_default_docker_compose() {
    local compose_file="$1"
    cat << 'EOF' > "$compose_file"
version: '3.8'

services:
  filebrowser:
    image: filebrowser/filebrowser:latest
    container_name: filebrowser
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - /home:/srv
      - ./filebrowser/config:/config
      - ./filebrowser/database:/database
    command: --config=/config/settings.json

  # Add other services as needed
EOF
    print_debug "✓ Created default docker-compose.yaml"
}

# Function to create default mavlink-router config if download fails
create_default_mavlink_config() {
    local config_file="$1"
    cat << 'EOF' > "$config_file"
[General]
TcpServerPort=5760
ReportStats=false
MavlinkDialect=auto

[UartEndpoint uart]
Device=/dev/ttyUSB0
Baud=57600

[UdpEndpoint groundstation]
Mode=Normal
Address=127.0.0.1
Port=14550
EOF
    print_debug "✓ Created default mavlink-router.conf"
}

# Function to run initial setup
run_setup() {
    print_info "Running initial system setup..."
    
    # Create directories
    create_directories
    
    # Download configuration files
    download_config_files
    
    print_success "Initial setup completed successfully!"
}

# Function to get user credentials
get_credentials() {
    print_debug "Starting credential collection"
    
    echo -n "Enter your email: "
    read -r USER_EMAIL
    print_debug "Email read successfully"
    
    echo -n "Enter your password: "
    read -s USER_PASSWORD
    echo  # New line after password input
    print_debug "Password read successfully"
    
    print_debug "Credentials received - email: $USER_EMAIL, password length: ${#USER_PASSWORD}"
    
    if [ -z "$USER_EMAIL" ] || [ -z "$USER_PASSWORD" ]; then
        print_error "Email and password cannot be empty"
        exit 1
    fi
    
    print_debug "Credentials validation passed"
}

# Function to initiate login flow and get action URL
get_login_flow() {
    # Send debug info to stderr so it doesn't get captured by command substitution
    print_debug "Initiating login flow..." >&2
    print_debug "Making request to: $KRATOS_URL/self-service/login/api" >&2
    
    local response
    response=$(curl -s -X GET -H "Accept: application/json" \
        "$KRATOS_URL/self-service/login/api")
    
    local curl_exit_code=$?
    print_debug "Curl exit code: $curl_exit_code" >&2
    
    if [ $curl_exit_code -ne 0 ]; then
        print_error "Failed to connect to Kratos server at $KRATOS_URL" >&2
        exit 1
    fi
    
    print_debug "Response received, length: ${#response}" >&2
    print_debug "First 200 chars of response: ${response:0:200}" >&2
    
    # Check if response is valid JSON
    if ! echo "$response" | jq empty 2>/dev/null; then
        print_error "Invalid JSON response from server" >&2
        print_error "Full response: $response" >&2
        exit 1
    fi
    
    print_debug "JSON is valid, extracting action URL..." >&2
    
    local action_url
    action_url=$(echo "$response" | jq -r '.ui.action // empty')
    
    print_debug "Extracted action_url: '$action_url'" >&2
    
    if [ -z "$action_url" ]; then
        print_error "Failed to get action URL from login flow" >&2
        exit 1
    fi
    
    print_debug "Action URL successfully extracted: $action_url" >&2
    # Only echo the action URL to stdout (this gets captured by command substitution)
    echo "$action_url"
}

# Function to perform login
perform_login() {
    local action_url="$1"
    local email="$2"
    local password="$3"
    
    # Send debug info to stderr so it doesn't interfere with command substitution
    print_debug "Attempting login for user: $email" >&2
    print_debug "Using action URL: $action_url" >&2
    
    local login_data
    login_data=$(cat <<EOF
{
    "identifier": "$email",
    "password": "$password",
    "method": "password"
}
EOF
)
    
    print_debug "Login data prepared" >&2
    print_debug "Making login request..." >&2
    
    local response
    response=$(curl -s -X POST \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        -d "$login_data" \
        "$action_url")
    
    local curl_exit_code=$?
    print_debug "Login curl exit code: $curl_exit_code" >&2
    
    if [ $curl_exit_code -ne 0 ]; then
        print_error "Login request failed with curl exit code: $curl_exit_code" >&2
        exit 1
    fi
    
    print_debug "Login response received, length: ${#response}" >&2
    print_debug "First 200 chars of login response: ${response:0:200}" >&2
    
    # Check if response is valid JSON
    if ! echo "$response" | jq empty 2>/dev/null; then
        print_error "Invalid JSON response from login endpoint" >&2
        exit 1
    fi
    
    # Check if login was successful by looking for session_token
    local session_token
    session_token=$(echo "$response" | jq -r '.session_token // empty')
    
    print_debug "Extracted session_token: '${session_token:0:20}...'" >&2
    
    if [ -z "$session_token" ]; then
        # Check for error messages in the UI
        local error_msg
        error_msg=$(echo "$response" | jq -r '.ui.messages[]?.text // empty' 2>/dev/null | head -1)
        
        if [ -z "$error_msg" ]; then
            error_msg=$(echo "$response" | jq -r '.error.message // .message // "Login failed - check credentials"' 2>/dev/null)
        fi
        
        print_error "Login failed: $error_msg" >&2
        
        # Show more details if available in debug mode
        if [ "$DEBUG" = "1" ]; then
            local error_details
            error_details=$(echo "$response" | jq -r '.ui.messages[]? | "\(.type): \(.text)"' 2>/dev/null)
            if [ -n "$error_details" ]; then
                print_error "Error details:" >&2
                echo "$error_details" >&2
            fi
            
            print_error "Full login response for debugging:" >&2
            echo "$response" | jq . 2>/dev/null || echo "$response" >&2
        fi
        
        exit 1
    fi
    
    print_debug "Login successful, returning response" >&2
    # Only echo the response to stdout (this gets captured)
    echo "$response"
}

# Function to get JWT token using session token
get_jwt_token() {
    local session_token="$1"
    
    print_debug "Fetching JWT token..." >&2
    print_debug "Using session token: ${session_token:0:20}..." >&2
    
    # Make request to whoami endpoint with Authorization header
    local whoami_url="$KRATOS_URL/sessions/whoami?tokenize_as=jwks_template_7days"
    print_debug "Making request to: $whoami_url" >&2
    
    local response
    response=$(curl -s -X GET \
        -H "Authorization: Bearer $session_token" \
        "$whoami_url")
    
    local curl_exit_code=$?
    print_debug "JWT curl exit code: $curl_exit_code" >&2
    
    if [ $curl_exit_code -ne 0 ]; then
        print_error "Failed to fetch JWT token, curl exit code: $curl_exit_code" >&2
        return 1
    fi
    
    print_debug "JWT response received, length: ${#response}" >&2
    print_debug "First 200 chars of JWT response: ${response:0:200}" >&2
    
    # Check if response is valid JSON
    if ! echo "$response" | jq empty 2>/dev/null; then
        print_error "Invalid JSON response from whoami endpoint" >&2
        if [ "$DEBUG" = "1" ]; then
            print_error "Full response: $response" >&2
        fi
        return 1
    fi
    
    local jwt_token
    jwt_token=$(echo "$response" | jq -r '.tokenized // empty')
    
    print_debug "Extracted JWT from .tokenized: '${jwt_token:0:30}...'" >&2
    
    if [ -z "$jwt_token" ]; then
        # Try alternative fields where JWT might be located
        jwt_token=$(echo "$response" | jq -r '.token // .jwt // empty')
        print_debug "Tried alternative fields, JWT: '${jwt_token:0:30}...'" >&2
        
        if [ -z "$jwt_token" ]; then
            print_error "Failed to extract JWT token from response" >&2
            if [ "$DEBUG" = "1" ]; then
                print_error "Available fields in response:" >&2
                echo "$response" | jq -r 'keys[]' 2>/dev/null >&2 || echo "Could not list keys" >&2
                print_error "Full JWT response:" >&2
                echo "$response" | jq . 2>/dev/null >&2 || echo "$response" >&2
            fi
            return 1
        fi
    fi
    
    print_debug "JWT token successfully obtained" >&2
    echo "$jwt_token"
}

# Function to extract and save session information
save_session_info() {
    local login_response="$1"
    local email="$2"
    
    print_debug "Extracting session information..."
    
    # Extract session information based on the official response structure
    local session_token user_id workspace_id jwt_token
    
    session_token=$(echo "$login_response" | jq -r '.session_token')
    user_id=$(echo "$login_response" | jq -r '.session.identity.id')
    
    # Extract workspace_id from session.identity.metadata_public.company_id
    workspace_id=$(echo "$login_response" | jq -r '.session.identity.metadata_public.company_id // empty')
    
    # Get JWT token using the session token
    jwt_token=$(get_jwt_token "$session_token")
    if [ $? -ne 0 ] || [ -z "$jwt_token" ]; then
        print_info "JWT token not available, continuing without it"
        jwt_token=""
    else
        print_debug "JWT token obtained successfully"
    fi
    
    # Check workspace_id availability
    if [ -z "$workspace_id" ]; then
        print_debug "No workspace_id found in session.identity.metadata_public.company_id"
        workspace_id=""
    else
        print_debug "Workspace ID found: $workspace_id"
    fi
    
    # Create the token file content
    local token_content
    token_content=$(jq -n \
        --arg token "$session_token" \
        --arg user_id "$user_id" \
        --arg workspace_id "$workspace_id" \
        --arg jwt_token "$jwt_token" \
        --arg email "$email" \
        '{
            "token": $token,
            "user_id": $user_id,
            "workspace_id": $workspace_id,
            "jwt_token": $jwt_token,
            "email": $email
        }')
    
    # Save to file
    echo "$token_content" > "$TOKEN_FILE"
    
    if [ $? -eq 0 ]; then
        print_success "Login successful! Session saved to: $TOKEN_FILE"
        print_info "User: $email (ID: $user_id)"
        if [ -n "$workspace_id" ]; then
            print_info "Workspace ID: $workspace_id"
        fi
        if [ -n "$jwt_token" ]; then
            print_info "JWT token: ${jwt_token:0:20}..."
        fi
    else
        print_error "Failed to save session information to file"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --debug         Enable debug output"
    echo "  -s, --setup         Run initial system setup (create directories and download configs)"
    echo "  --setup-only        Run setup only (don't perform login)"
    echo "  --install-dev       Install full development environment (Docker, code-server, Tailscale)"
    echo "  --dev-only          Install development environment only (no login)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  DEBUG=1             Enable debug output (alternative to -d)"
    echo ""
    echo "Setup creates:"
    echo "  • \$HOME/.skyclient directory structure"
    echo "  • \$HOME/.skyclient/filebrowser/config & database directories"
    echo "  • Configuration files from remote URLs with fallbacks"
    echo "  • \$HOME/autrikos directory"
    echo ""
    echo "Development environment installs:"
    echo "  • Basic tools (git, wget, curl, nano, net-tools)"
    echo "  • Docker"
    echo "  • code-server (accessible on port 8085, password: asdf)"
    echo "  • Tailscale"
}

# Main function
main() {
    print_debug "Entered main function"
    print_info "Ory Kratos Login Script"
    
    # Check dependencies
    check_dependencies
    
    # Create basic token directory (setup creates more comprehensive structure)
    if [ ! -d "$TOKEN_DIR" ]; then
        print_debug "Creating basic token directory: $TOKEN_DIR"
        mkdir -p "$TOKEN_DIR"
    fi
    
    # Get user credentials
    get_credentials
    
    # Get login flow and action URL
    print_debug "Getting login flow..."
    action_url=$(get_login_flow)
    print_debug "Retrieved action URL: $action_url"
    
    # Perform login
    print_debug "Performing login..."
    login_response=$(perform_login "$action_url" "$USER_EMAIL" "$USER_PASSWORD")
    print_debug "Login completed, response length: ${#login_response}"
    
    # Save session information
    save_session_info "$login_response" "$USER_EMAIL"
    
    print_success "Login process completed successfully!"
    print_debug "Exiting main function"
}

# Parse command line arguments
RUN_SETUP=0
SETUP_ONLY=0
INSTALL_DEV=0
DEV_ONLY=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--debug)
            DEBUG=1
            shift
            ;;
        -s|--setup)
            RUN_SETUP=1
            shift
            ;;
        --setup-only)
            RUN_SETUP=1
            SETUP_ONLY=1
            shift
            ;;
        --install-dev)
            INSTALL_DEV=1
            shift
            ;;
        --dev-only)
            INSTALL_DEV=1
            DEV_ONLY=1
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Run main function
print_debug "About to call main function"

# Install development environment if requested
if [ "$INSTALL_DEV" = "1" ]; then
    install_dev_environment
fi

# Run setup if requested
if [ "$RUN_SETUP" = "1" ]; then
    run_setup
fi

# Run login unless setup-only or dev-only was specified
if [ "$SETUP_ONLY" = "0" ] && [ "$DEV_ONLY" = "0" ]; then
    main "$@"
else
    if [ "$SETUP_ONLY" = "1" ]; then
        print_info "Setup-only mode completed"
    fi
    if [ "$DEV_ONLY" = "1" ]; then
        print_info "Development environment installation completed"
    fi
fi

print_debug "Script completed"
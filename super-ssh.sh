#!/bin/bash

# Configuration
USER="root"
PASSWORDS=("qw401hng" "KEI215sak")  # List of passwords to try
SUBNETS=(5 9 0)

# Default start IP for subnets
DEFAULT_START_IP=2

# Function to get start IP for a specific subnet
get_subnet_start_ip() {
    local subnet=$1

    case $subnet in
        5)
            echo 165  # Subnet 5 starts from .165
            ;;
        *)
            echo $DEFAULT_START_IP
            ;;
    esac
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Flag to track if user wants to stop
STOP_REQUESTED=false

# Trap Ctrl+C (SIGINT) to allow graceful exit
trap 'echo -e "\n${YELLOW}[Info] Stopping connection attempts...${NC}"; STOP_REQUESTED=true' INT

# Function to prompt for target address
prompt_target() {
    echo -e "${YELLOW}Enter target address (format: 10.10.*.*)${NC}"
    read -r TARGET

    # Validate format
    if [[ ! $TARGET =~ ^10\.10\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid format. Expected 10.10.*.*${NC}"
        exit 1
    fi

    echo "$TARGET"
}

# Function to check if sshpass is installed
check_dependencies() {
    if ! command -v sshpass &> /dev/null; then
        echo -e "${RED}Error: sshpass is not installed${NC}"
        echo "Install it with: brew install hudochenkov/sshpass/sshpass (macOS) or apt-get install sshpass (Linux)"
        exit 1
    fi
}

# Function to try direct SSH connection
try_direct_ssh() {
    local target=$1
    local password=$2

    sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        $USER@$target 2>/dev/null

    return $?
}

# Function to check if host is alive
check_host_alive() {
    local host=$1

    # Ping with 1 second timeout, 1 packet
    ping -c 1 -W 1 "$host" &>/dev/null
    return $?
}

# Function to authenticate to a jump host and return the working password
try_authenticate_jump_host() {
    local jump_host=$1

    # Try each password
    for password in "${PASSWORDS[@]}"; do
        echo -e "${YELLOW}[Auth] Trying password for $jump_host...${NC}"

        local auth_test
        auth_test=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=5 \
            -o NumberOfPasswordPrompts=1 \
            -o PubkeyAuthentication=no \
            -o PreferredAuthentications=password \
            $USER@$jump_host "echo 'AUTH_OK'" 2>&1)

        if [[ "$auth_test" == *"AUTH_OK"* ]]; then
            echo -e "${GREEN}[Auth] Successfully authenticated to $jump_host${NC}"
            echo "$password"  # Return the working password
            return 0
        fi
    done

    echo -e "${RED}[Auth] All passwords failed for $jump_host${NC}"
    return 1
}

# Function to try SSH connection through a specific jump host
try_ssh_via_jump_host() {
    local jump_host=$1
    local target=$2
    local password=$3

    # Try SSH with ProxyJump using sshpass for both connections
    # Capture stderr to show errors
    local ssh_error
    ssh_error=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=3 \
        -o ProxyCommand="sshpass -p $password ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=3 -W %h:%p $USER@$jump_host" \
        $USER@$target 'exit' 2>&1)

    local result=$?

    # Show error if connection failed
    if [ $result -ne 0 ] && [ -n "$ssh_error" ]; then
        echo -e "${RED}[SSH Error] $ssh_error${NC}"
    fi

    return $result
}

# Function to scan subnet and try connections through each alive host
try_ssh_via_subnet() {
    local subnet=$1
    local target=$2

    # Get start IP for this subnet (use default if not configured)
    local start_ip=$(get_subnet_start_ip "$subnet")

    echo -e "${YELLOW}[Scanning] Subnet 10.10.${subnet}.0/24 (starting from .${start_ip})...${NC}"

    # Iterate through hosts in subnet (start_ip to .254)
    for ((host_id=start_ip; host_id<=254; host_id++)); do
        # Check if user requested to stop
        if [ "$STOP_REQUESTED" = true ]; then
            echo -e "${YELLOW}[Info] Skipping remaining hosts in subnet${NC}"
            return 1
        fi

        local jump_host="10.10.${subnet}.${host_id}"

        # Skip if this is the target itself
        if [ "$jump_host" = "$target" ]; then
            continue
        fi

        # Check if host is alive
        echo -ne "${YELLOW}[Ping] $jump_host...${NC} "
        if check_host_alive "$jump_host"; then
            echo -e "${GREEN}alive${NC}"
            echo -e "${YELLOW}[Info] Attempting to use $jump_host as jump host...${NC}"

            # Try to authenticate to jump host with all passwords
            local working_password
            working_password=$(try_authenticate_jump_host "$jump_host")

            if [ $? -ne 0 ]; then
                echo -e "${RED}[Skip] Cannot authenticate to $jump_host, skipping...${NC}"
                continue
            fi

            echo -e "${GREEN}[Success] Authenticated to $jump_host with working password${NC}"

            # First check if target is reachable from jump host
            echo -e "${YELLOW}[Test] Checking if $target is reachable from $jump_host...${NC}"
            local ping_test
            ping_test=$(sshpass -p "$working_password" ssh -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o ConnectTimeout=3 \
                -o NumberOfPasswordPrompts=1 \
                -o PubkeyAuthentication=no \
                -o PreferredAuthentications=password \
                $USER@$jump_host "ping -c 1 -W 1 $target &>/dev/null && echo 'reachable' || echo 'unreachable'" 2>/dev/null)

            if [[ "$ping_test" == *"reachable"* ]]; then
                echo -e "${GREEN}[Test] $target is reachable from $jump_host${NC}"

                # Try to connect through this jump host
                echo -e "${YELLOW}[Attempt] Connecting to $target via $jump_host...${NC}"
                if try_ssh_via_jump_host "$jump_host" "$target" "$working_password"; then
                    echo -e "${GREEN}✓ Successfully connected to $target via $jump_host${NC}"
                    echo -e "${GREEN}Use this command to connect:${NC}"
                    echo -e "ssh -o ProxyCommand=\"sshpass -p PASSWORD ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p $USER@$jump_host\" $USER@$target"
                    return 0
                else
                    echo -e "${RED}✗ Failed to connect via $jump_host, trying next host...${NC}"
                    # Continue to next host in subnet
                fi
            else
                echo -e "${RED}[Test] $target is NOT reachable from $jump_host${NC}"

                # Run diagnostics to find out why
                echo -e "${YELLOW}[Debug] Running diagnostics...${NC}"

                # Ping test with details
                echo -e "${YELLOW}=== Ping Test ===${NC}"
                sshpass -p "$working_password" ssh -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o ConnectTimeout=5 \
                    -o NumberOfPasswordPrompts=1 \
                    -o PubkeyAuthentication=no \
                    -o PreferredAuthentications=password \
                    -o LogLevel=ERROR \
                    $USER@$jump_host "ping -c 3 -W 2 $target" 2>&1

                # Route information
                echo -e "${YELLOW}=== Route to Target ===${NC}"
                sshpass -p "$working_password" ssh -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o ConnectTimeout=5 \
                    -o NumberOfPasswordPrompts=1 \
                    -o PubkeyAuthentication=no \
                    -o PreferredAuthentications=password \
                    -o LogLevel=ERROR \
                    $USER@$jump_host "ip route get $target 2>&1 || route -n get $target 2>&1" 2>&1

                # Interface info
                echo -e "${YELLOW}=== Network Interfaces ===${NC}"
                sshpass -p "$working_password" ssh -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o ConnectTimeout=5 \
                    -o NumberOfPasswordPrompts=1 \
                    -o PubkeyAuthentication=no \
                    -o PreferredAuthentications=password \
                    -o LogLevel=ERROR \
                    $USER@$jump_host "ip addr show 2>&1 || ifconfig 2>&1" 2>&1 | head -30

                echo -e "${YELLOW}[Debug] Diagnostics complete${NC}"
            fi
        else
            echo -e "${RED}dead${NC}"
        fi
    done

    echo -e "${RED}No alive hosts found in subnet 10.10.${subnet}.0/24${NC}"
    return 1
}

# Main logic
main() {
    check_dependencies

    # Get target address
    if [ $# -eq 0 ]; then
        TARGET=$(prompt_target)
    else
        TARGET=$1

        # Validate format
        if [[ ! $TARGET =~ ^10\.10\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}Error: Invalid format. Expected 10.10.*.*${NC}"
            exit 1
        fi
    fi

    echo -e "\n${GREEN}Target: $TARGET${NC}"
    echo -e "${GREEN}User: $USER${NC}"
    echo -e "Attempting to establish SSH connection...\n"

    # Try direct connection first with all passwords
    echo -e "${YELLOW}[Attempt] Direct connection to $TARGET...${NC}"
    for password in "${PASSWORDS[@]}"; do
        if try_direct_ssh "$TARGET" "$password"; then
            echo -e "${GREEN}✓ Successfully connected directly to $TARGET${NC}"
            exit 0
        fi
    done

    echo -e "${RED}✗ Direct connection failed with all passwords${NC}\n"

    # Try each subnet as jump host
    for subnet in "${SUBNETS[@]}"; do
        if try_ssh_via_subnet "$subnet" "$TARGET"; then
            exit 0
        fi
        echo -e "${RED}✗ Failed via subnet 10.10.${subnet}.0/24${NC}\n"
    done

    echo -e "${RED}Failed to connect through all available paths${NC}"
    exit 1
}

# Run main function
main "$@"

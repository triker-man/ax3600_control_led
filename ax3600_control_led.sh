#!/bin/bash

# Define LED paths as constants in an associative array.
declare -A LEDS=(
    [AIOT_BLUE]="/sys/class/leds/blue:aiot/trigger"
    [NETWORK_YELLOW]="/sys/class/leds/yellow:network/trigger"
    [NETWORK_BLUE]="/sys/class/leds/blue:network/trigger"
    [SYSTEM_YELLOW]="/sys/class/leds/yellow:system/trigger"
    [SYSTEM_BLUE]="/sys/class/leds/blue:system/trigger"
)

# Log file for errors and pending Telegram messages
ERROR_LOG_DATE=$(date '+%Y-%m-%d')
ERROR_LOG="/overlay/ax3600_control_led_$ERROR_LOG_DATE.log"
PENDING_MSGS="/overlay/ax3600_control_led_pending.msg"

# Configuration variables
WAN_IP="192.168.100.1"
INET_IP="8.8.8.8"
RPI_IP="192.168.1.10"
SSH_PORT="22"

# Initial state of tests (0 for OK, 1 for FAIL)
declare -A test_states=(
    [WAN]=0 [INET]=0 [RPI]=0 [RPISSH]=0 [5G]=0 [INTERNET_CONNECTIVITY]=0
)

# Function to send a message to Telegram
send_telegram_message() {
    local message="$1"
    local GROUP_ID="XXXXXXXXXXXXXXX"
    local BOT_TOKEN="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" 
    
    # Try to send message. If it fails, store it in the pending queue
    wget-ssl -qO- -o /dev/null --post-data="chat_id=$GROUP_ID&parse_mode=markdown&text=$message" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" > /dev/null

    if [ $? -ne 0 ]; then
        # If no connectivity, store the message in the pending queue
        echo "$message" >> "$PENDING_MSGS"
    fi
}

# Function to send pending messages when internet connectivity is restored
send_pending_messages() {
    if [ -f "$PENDING_MSGS" ]; then
        # Read all pending messages and concatenate them
        local pending_messages=$(cat "$PENDING_MSGS")
        
        # Check if there are any pending messages to send
        if [ -n "$pending_messages" ]; then
            local full_message="*REENVIO DE MENSAJES ENCOLADOS:*%0A\`$pending_messages\`"
            
            # Send all pending messages in a single Telegram message
            send_telegram_message "$full_message"
            
            # Clear the queue after sending all messages
            : > "$PENDING_MSGS"
        fi
    fi
}

# Generic function to control LEDs
control_led() {
    local led=$1 action=$2
    case $action in
        on) echo default-on > "${LEDS[$led]}" ;;
        off) echo none > "${LEDS[$led]}" ;;
        blink) echo timer > "${LEDS[$led]}" ;;
        heartbeat) echo heartbeat > "${LEDS[$led]}" ;;
    esac
}

# Function to initialize the LEDs by turning them off and setting specific ones to blink
init_leds() {
    for led in "${!LEDS[@]}"; do
        control_led "$led" off
    done
    control_led "AIOT_BLUE" blink
    control_led "NETWORK_BLUE" blink
    control_led "SYSTEM_BLUE" blink
}

# Function to perform connectivity tests using ping
run_ping_test() {
    ping -q -c 3 -W 1 "$1" &> /dev/null && echo "OK" || echo "FAIL"
}

# Function to test SSH connection
run_ssh_test() {
    wget-ssl --timeout=3 --tries=1 -O- "$1:$2" -o /dev/null 2>&1 | grep -q OpenSSH && echo "OK" || echo "FAIL"
}

# Function to check if 5G devices are connected
run_5g_test() {
    iwinfo phy1-ap0 assoclist &> /dev/null && echo "OK" || echo "FAIL"
}

# Log and handle errors and recoveries
log_event() {
    local type="$1" message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $type: $message" >> "$ERROR_LOG"
    send_telegram_message "[$timestamp] $type: $message"
}

# Function to handle test results, logging errors and recoveries
handle_test_result() {
    local test_name="$1" result="$2" fail_msg="$3" recover_msg="$4"
    
    if [ "$result" = "FAIL" ] && [ "${test_states[$test_name]}" -eq 0 ]; then
        log_event "ERROR" "$fail_msg"
        test_states[$test_name]=1
    elif [ "$result" = "OK" ] && [ "${test_states[$test_name]}" -eq 1 ]; then
        log_event "RECOVERY" "$recover_msg"
        test_states[$test_name]=0
    fi
}

# Main function to run all the tests
perform_tests() {
    local test_wan=$(run_ping_test "$WAN_IP")
    local test_inet=$(run_ping_test "$INET_IP")
    local test_rpi=$(run_ping_test "$RPI_IP")
    local test_rpissh=$(run_ssh_test "$RPI_IP" "$SSH_PORT")
    local test_5g=$(run_5g_test)

    handle_test_result "WAN" "$test_wan" "WAN test failed (IP: $WAN_IP)" "WAN test recovered (IP: $WAN_IP)"
    handle_test_result "INET" "$test_inet" "Internet connectivity test failed (IP: $INET_IP)" "Internet connectivity test recovered (IP: $INET_IP)"
    handle_test_result "RPI" "$test_rpi" "Ping to Raspberry Pi failed (IP: $RPI_IP)" "Ping to Raspberry Pi recovered (IP: $RPI_IP)"
    handle_test_result "RPISSH" "$test_rpissh" "SSH connection to Raspberry Pi failed (IP: $RPI_IP, Port: $SSH_PORT)" "SSH connection to Raspberry Pi recovered (IP: $RPI_IP, Port: $SSH_PORT)"
    handle_test_result "5G" "$test_5g" "5G device connection test failed" "5G device connection test recovered"

    # LED control based on WAN and INET results
    if [ "$test_wan" = "OK" ]; then
        control_led "NETWORK_YELLOW" on
    else
        control_led "NETWORK_YELLOW" heartbeat
    fi

    if [ "$test_inet" = "OK" ]; then
        control_led "NETWORK_BLUE" on
    else
        control_led "NETWORK_BLUE" blink
    fi

    if [ "$test_rpissh" = "FAIL" ]; then
        control_led "SYSTEM_YELLOW" blink
        control_led "SYSTEM_BLUE" blink
    else
        control_led "SYSTEM_YELLOW" on
        control_led "SYSTEM_BLUE" on
    fi

    [ "$test_5g" = "OK" ] && control_led "AIOT_BLUE" on || control_led "AIOT_BLUE" blink

    # If Internet connectivity is restored, send pending messages
    if [ "$test_inet" = "OK" ] && [ "${test_states[INTERNET_CONNECTIVITY]}" -eq 1 ]; then
        send_pending_messages
        test_states[INTERNET_CONNECTIVITY]=0  # Reset Internet connectivity state to OK
    elif [ "$test_inet" = "FAIL" ] && [ "${test_states[INTERNET_CONNECTIVITY]}" -eq 0 ]; then
        test_states[INTERNET_CONNECTIVITY]=1  # Mark no connectivity state
    fi
}

# Clean up LEDs on exit
cleanup() {
    echo "Turning off LEDs and exiting script..."
    init_leds
    exit 0
}

# Capture signals to clean up
trap cleanup SIGINT SIGTERM

# Initialize LEDs and run tests in a loop
init_leds
while true; do
    perform_tests
    sleep 3
done

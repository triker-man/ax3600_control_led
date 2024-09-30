#!/bin/bash

# Define LED paths as constants in an associative array
declare -A LEDS=(
    [AIOT_BLUE]="/sys/class/leds/blue:aiot/trigger"
    [NETWORK_YELLOW]="/sys/class/leds/yellow:network/trigger"
    [NETWORK_BLUE]="/sys/class/leds/blue:network/trigger"
    [SYSTEM_YELLOW]="/sys/class/leds/yellow:system/trigger"
    [SYSTEM_BLUE]="/sys/class/leds/blue:system/trigger"
)

# Error log file
ERROR_LOG_DATE=$(date '+%Y-%m-%d')
ERROR_LOG="/overlay/ax3600_control_led_$ERROR_LOG_DATE.log"

# Variables to track the status of tests (0 for OK, 1 for FAIL)
declare -A test_states=(
    [WAN]=0
    [INET]=0
    [RPI]=0
    [RPISSH]=0
    [5G]=0
)

# Send to Telegram
send_telegram_message() {
    GROUP_ID="XXXXXXXXXXXXXXX"                                                                                         
    BOT_TOKEN="XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX" 

    local message="$1"
    wget -qO- --post-data="chat_id=$GROUP_ID&text=$message" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" > /dev/null
}

# Generic function to control LEDs
control_led() {
    local led=$1
    local action=$2
    case $action in
        on) echo default-on > "${LEDS[$led]}" ;;
        off) echo none > "${LEDS[$led]}" ;;
        blink) echo timer > "${LEDS[$led]}" ;;
        heartbeat) echo heartbeat > "${LEDS[$led]}" ;;
    esac
}

# Initialize LEDs
init_leds() {
    for led in "${!LEDS[@]}"; do
        control_led "$led" off
    done
    control_led "AIOT_BLUE" blink
    control_led "NETWORK_BLUE" blink
    control_led "SYSTEM_BLUE" blink
}

# Test configuration (IPs and parameters)
WAN_IP="192.168.100.1"
INET_IP="8.8.8.8"
RPI_IP="192.168.1.10"
SSH_PORT="22"

# Function to perform connectivity tests using ping
run_ping_test() {
    local ip=$1
    ping -q -c 3 -W 1 "$ip" &> /dev/null && echo "OK" || echo "FAIL"
}

# Function to check SSH connection
run_ssh_test() {
    local ip=$1
    local port=$2
    wget-ssl --timeout=3 --tries=1 -O- "$ip:$port" -o /dev/null 2>&1 | grep -q OpenSSH && echo "OK" || echo "FAIL"
}

# Function to check if 5G devices are connected
run_5g_test() {
    iwinfo phy1-ap0 assoclist &> /dev/null && echo "OK" || echo "FAIL"
}

# Function to handle critical errors, logging specific failed tests
handle_critical_failure() {
    local error_message=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] ERROR: $error_message" 
    echo $message >> "$ERROR_LOG"    # Log to file
    send_telegram_message "$message" # Send to Telegram
}

# Function to handle recoveries and log when a failure is resolved
handle_recovery() {
    local recovery_message=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local message="[$timestamp] RECOVERY: $recovery_message"
    echo $message >> "$ERROR_LOG"    # Log to file                                                                                 
    send_telegram_message "$message" # Send to Telegram     
}

# Main function to perform tests
perform_tests() {
    local test_wan=$(run_ping_test "$WAN_IP")
    local test_inet=$(run_ping_test "$INET_IP")
    local test_rpi=$(run_ping_test "$RPI_IP")
    local test_rpissh=$(run_ssh_test "$RPI_IP" "$SSH_PORT")
    local test_5g=$(run_5g_test)

    # Check and log test failures or recoveries
    # WAN
    if [ "$test_wan" = "FAIL" ] && [ "${test_states[WAN]}" -eq 0 ]; then
        handle_critical_failure "WAN test failed (IP: $WAN_IP)"
        test_states[WAN]=1
    elif [ "$test_wan" = "OK" ] && [ "${test_states[WAN]}" -eq 1 ]; then
        handle_recovery "WAN test recovered (IP: $WAN_IP)"
        test_states[WAN]=0
    fi

    # INET
    if [ "$test_inet" = "FAIL" ] && [ "${test_states[INET]}" -eq 0 ]; then
        handle_critical_failure "Internet connectivity test failed (IP: $INET_IP)"
        test_states[INET]=1
    elif [ "$test_inet" = "OK" ] && [ "${test_states[INET]}" -eq 1 ]; then
        handle_recovery "Internet connectivity test recovered (IP: $INET_IP)"
        test_states[INET]=0
    fi

    # RPI
    if [ "$test_rpi" = "FAIL" ] && [ "${test_states[RPI]}" -eq 0 ]; then
        handle_critical_failure "Ping to Raspberry Pi failed (IP: $RPI_IP)"
        test_states[RPI]=1
    elif [ "$test_rpi" = "OK" ] && [ "${test_states[RPI]}" -eq 1 ]; then
        handle_recovery "Ping to Raspberry Pi recovered (IP: $RPI_IP)"
        test_states[RPI]=0
    fi

    # RPISSH
    if [ "$test_rpissh" = "FAIL" ] && [ "${test_states[RPISSH]}" -eq 0 ]; then
        handle_critical_failure "SSH connection to Raspberry Pi failed (IP: $RPI_IP, Port: $SSH_PORT)"
        test_states[RPISSH]=1
    elif [ "$test_rpissh" = "OK" ] && [ "${test_states[RPISSH]}" -eq 1 ]; then
        handle_recovery "SSH connection to Raspberry Pi recovered (IP: $RPI_IP, Port: $SSH_PORT)"
        test_states[RPISSH]=0
    fi

    # 5G
    if [ "$test_5g" = "FAIL" ] && [ "${test_states[5G]}" -eq 0 ]; then
        handle_critical_failure "5G device connection test failed"
        test_states[5G]=1
    elif [ "$test_5g" = "OK" ] && [ "${test_states[5G]}" -eq 1 ]; then
        handle_recovery "5G device connection test recovered"
        test_states[5G]=0
    fi

    # LED control based on test results
    if [ "$test_wan" = "OK" ]; then
        if [ "$test_inet" = "OK" ]; then
            control_led "NETWORK_YELLOW" on
            control_led "NETWORK_BLUE" on
        else
            control_led "NETWORK_YELLOW" blink
            control_led "NETWORK_BLUE" blink
        fi
    else
        control_led "NETWORK_YELLOW" heartbeat
        control_led "NETWORK_BLUE" heartbeat
    fi

    if [ "$test_rpissh" = "FAIL" ]; then
        if [ "$test_rpi" = "FAIL" ]; then
            control_led "SYSTEM_YELLOW" blink
            control_led "SYSTEM_BLUE" blink
        else
            control_led "SYSTEM_YELLOW" heartbeat
            control_led "SYSTEM_BLUE" heartbeat
        fi
    else
        control_led "SYSTEM_YELLOW" on
        control_led "SYSTEM_BLUE" on
    fi

    if [ "$test_5g" = "OK" ]; then
        control_led "AIOT_BLUE" on
    else
        control_led "AIOT_BLUE" blink
    fi
}

# Initialize LEDs
init_leds

# Run tests in a loop
while true; do
    perform_tests
    sleep 3
done

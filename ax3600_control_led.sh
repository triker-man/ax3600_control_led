#!/bin/ash

# Define LED paths as constants
LED_AIOT______BLUE="/sys/class/leds/blue:aiot/trigger"
LED_NETWORK_YELLOW="/sys/class/leds/yellow:network/trigger"
LED_NETWORK___BLUE="/sys/class/leds/blue:network/trigger"
LED_SYSTEM__YELLOW="/sys/class/leds/yellow:system/trigger"
LED_SYSTEM____BLUE="/sys/class/leds/blue:system/trigger"

# Function to turn on a LED
turn_on_led() {
    echo default-on > "$1"
}

# Function to turn off a LED
turn_off_led() {
    echo none > "$1"
}

# Function to turn blink a LED
turn_blink_led() {
    echo timer > "$1"
}

# Function to beat a LED
turn_beat_led() {
    echo heartbeat > "$1"
}

# Initialize LEDs
init_leds() {  
        turn_blink_led "$LED_AIOT______BLUE"
        turn_blink_led "$LED_NETWORK_YELLOW"
        turn_blink_led "$LED_NETWORK___BLUE"
        turn_blink_led "$LED_SYSTEM__YELLOW"
        turn_blink_led "$LED_SYSTEM____BLUE"
} 



# Function to perform tests
perform_tests() {
    # Perform tests and store results
    Test_WAN=$(ping -q -c 3 -W 1 192.168.100.1 > /dev/null 2>&1 && echo "OK" || echo "FAIL")
    Test_INET=$(ping -q -c 3 -W 1 8.8.8.8 > /dev/null 2>&1 && echo "OK" || echo "FAIL")
    Test_RPI=$(ping -q -c 3 -W 1 192.168.1.10 > /dev/null 2>&1 && echo "OK" || echo "FAIL")
    Test_RPISSH=$(wget --timeout=3 --tries=1 -O- 192.168.1.10:22 2>&1 | grep OpenSSH && echo "OK" || echo "FAIL")
    Test_5G=$(iwinfo wlan1 assoclist > /dev/null 2>&1 && echo "OK" || echo "FAIL")

    # Control dependencies between tests
    if [ "$Test_WAN" = "OK" ]; then
          if [ "$Test_INET" = "OK" ]; then
                turn_on_led "$LED_NETWORK_YELLOW"
                turn_on_led "$LED_NETWORK___BLUE"
        else
                turn_blink_led "$LED_NETWORK_YELLOW"
                turn_blink_led "$LED_NETWORK___BLUE"
        fi
    else
        turn_beat_led "$LED_NETWORK_YELLOW"
        turn_beat_led "$LED_NETWORK___BLUE"
    fi

    if [ "$Test_RPISSH" = "FAIL" ]; then
        if [ "$Test_RPI" = "FAIL" ]; then
                turn_blink_led "$LED_SYSTEM__YELLOW"
                turn_blink_led "$LED_SYSTEM____BLUE"
        else
                turn_beat_led "$LED_SYSTEM__YELLOW"
                turn_beat_led "$LED_SYSTEM____BLUE"
        fi
    else
        turn_on_led "$LED_SYSTEM__YELLOW"
        turn_on_led "$LED_SYSTEM____BLUE"
    fi

    if [ "$Test_5G" = "OK" ]; then
        turn_on_led "$LED_AIOT______BLUE"
    else
        turn_blink_led "$LED_AIOT______BLUE"
    fi
}
# Poweroff all leds and secuence.
init_leds

# Execute tests indefinitely
while true; do
    perform_tests
done

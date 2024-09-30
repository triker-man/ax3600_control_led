## ax3600_control_led
Script for Xiaomi AX3600 with OpenWRT.
Perform checks and notify results on router LEDs.
Added: Test changelog to a file.
Added: Test changelog to Telegram
Added: Offline queue for Telegram messages.
<hr>

<b>Install:</b>
- Copy script to /overlay/ax3600_control_led.sh 
- chmod a+x ax3600_control_led.sh
- edit /etc/rc.local.
  
  add before exit 0:
  
  /overlay/ax3600_control_led.sh &


## Operation:
- Test WAN:
  
  Try 3 pings to local IP WAN exit (192.168.100.1)
- Test INET:
  
  Try 3 pings to remote IP (8.8.8.8)

  ** dependency of Test_WAN for Test_INET


- Test RPI:
  
  Try 3 pings to local IP (Raspberry Pi 192.168.1.10)
- Test RPISSH:
  
  Try open SSH (TCP 22) to Raspberry Pi

  ** dependency of Test_RPI for Test_RPISSH

- Test 5G:
  
  Check if 5G Wireless interface is enable
  

References:
https://openwrt.org/docs/guide-user/base-system/led_configuration
  
  
  
  

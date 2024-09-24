#!/bin/bash
#

#########################################################################################
# This script is designed to give users a warning that their computer has been on for 
# too long and needs to reboot.
# It can be used with a Launch Daemon or via MDM script.
# This is version 3.7
echo "Running ScheduleReboot script version 3.7"
#########################################################################################
#
# The list of variables, their purpose, and override parameters:
# uptimeLimit, $4 		= Max number of days before a reboot is required.
#
# deferralLimit, $5		= How many days before the uptimeLimit the user gets notified, 
#						and how many days they may defer before the reboot is forced.
#
# testUptime, $6		= Leave this blank in production. 
#						When testing the script, how many days of uptime you want to 
#						imitate.
#
# countdownTimer, $7	= How many minutes you want to give users before the computer 
#						reboots when the deferral limit has been reached.
#
# excluded_apps, $8		= Any apps you don't want to gracefully quit, or that need to  
#						stay open during the shutdown process. Put these in "" and 
#						separate with spaces instead of comas. 
#
# messageIcon, $9		= If you have a unique .png file you'd like to show instead of 
#						the built-in alert icon.
#
# scheduledRebootTime, $10	= Time you want the computer to reboot. Should align with the
#						companion launchdaemon so the computer only reboots after 
#						this time.
#
# testRebootTime		= Leave this blank in production.
#						When testing the script, this shortens the reboot time so you don't
#						have to wait until the scheduledRebootTime to test the deferal.

# Function to write a message to the jamf log file
log_message() {
    local log_file="/var/log/reboot_script.log"  # Correct log location
    
    # Create the log file if it doesn't exist and set correct permissions
    if [ ! -f "$log_file" ]; then
        touch "$log_file"
        chmod 644 "$log_file"
    fi

    local log_prefix=("["$1"] - ")
    local message="${log_prefix}$2"

    # Check if message is provided
    if [ -z "$message" ]; then
        echo "Log message not provided"
        return 1
    fi

    # Append the message to the log file with a timestamp
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$log_file"
}
log_message "REBOOT-SCHEDULER" "------ BEGIN REBOOT SCHEDULER -----"
log_message "REBOOT-SCHEDULER" "Running ScheduleReboot script version 3.6"

###### Set your variables here. #######

# Limit for how many days before a computer must reboot.
uptimeLimit=5
if [ ! -z "$4" ]; then
	uptimeLimit=$4
fi
log_message "uptimeLimit" "$uptimeLimit"

# How many days they are allowed to defer before they must reboot.
# This is also how many days before the uptimeLimit they will start seeing notifications.
deferralLimit=2
if [ ! -z "$5" ]; then
	deferralLimit=$5
fi
log_message "deferralLimit" "$deferralLimit"

# Used to test the script. Set the uptime length you want to test here.
# If you set a number here, it will not reboot the computer, but will show the messages.
testUptime=""
if [ ! -z "$6" ]; then
	testUptime=$6
fi
if [ ! -z "$testUptime" ]; then
	testMode=1
	log_message "TESTING_MODE" "testUptime was set to $testUptime so test mode is active."
fi
log_message "testUptime" "$testUptime"

# How many minutes users have before the message times out and the computer reboots.
countdownTimer=10
if [ ! -z "$7" ]; then
	countdownTimer=$7
fi
log_message "countdownTimer" "$countdownTimer"

# Any specific apps you don't want to force quit. Best to leave this alone.
excluded_apps=("Terminal" "Self Service" "Finder")
if [ ! -z "$8" ]; then
    IFS=' ' read -r -a excluded_apps <<< "$8"
fi
for app in "${excluded_apps[@]}"; do
    log_message "excluded_apps-LIST" "$app"
done

# If you have a custom icon you want to use for the notifications, otherwise use a native one.
messageIcon="/Users/Shared/Jamf/ITSLogo.v4.png"
if [ ! -z "$9" ]; then
	messageIcon=$9
fi
if [[ ! -f $messageIcon ]]; then
	messageIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"
	log_message "messageIcon-MISSING" "Unique messageIcon not found. Resetting it to: $messageIcon"   
fi
log_message "messageIcon" "Icon set to: $messageIcon"
echo "[messageIcon] -- Icon set to: $messageIcon"

# What time should the script enforce the reboot? Written in 24-hour format with leading 0
scheduledRebootTime="18:00"
testRebootTime=""

if [ -n "$testRebootTime" ]; then
    scheduledRebootTime=$(date -v+"${testRebootTime}M" +"%H:%M")
fi

log_message "scheduledRebootTime" "Scheduled reboot time set to $scheduledRebootTime"

#######################################################
# Variables set by the environment. Edit with caution #
#######################################################

# Uptime of the computer, measured in days.
if [ ! -z $testUptime ]; then
# 	Override if testUptime is filled in.
    uptimeDays=$testUptime
   	echo "[uptime_check-TEST] -- Computer reporting uptime as: $uptimeDays"
else
    uptime_output=$(uptime)
    uptimeDays=0
	log_message "uptime_check" "Computer reporting uptime as:"
	log_message "uptime_check" "$uptime_output"
	echo "[uptime_check] -- Computer reporting uptime as:"
	echo "[uptime_check] -- $uptime_output"
	
    if [[ "$uptime_output" =~ ([0-9]+)\ day ]]; then
        uptimeDays=${BASH_REMATCH[1]}
    elif [[ "$uptime_output" =~ ([0-9]+): ]]; then
        uptimeDays=0
    else
        uptimeDays=0
    fi
fi
log_message "uptime" "uptimeDays set to $uptimeDays."
echo "[uptime] -- uptimeDays set to $uptimeDays."

# Days left before the uptimeLimit is reached.
remainingDays=$((uptimeLimit - uptimeDays))

# New logic to handle negative remainingDays
if [ $remainingDays -lt 0 ]; then
    log_message "remainingDays" "remainingDays is negative: $remainingDays. Immediate reboot is required."
    echo "[remainingDays] -- remainingDays is negative: $remainingDays. Immediate reboot is required."
else
    log_message "remainingDays" "remainingDays set to $remainingDays."
    echo "[remainingDays] -- remainingDays set to $remainingDays."
fi

# Set the path to jamfHelper
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

# Check if jamfHelper exists and is executable
if [[ ! -x "$jamfHelper" ]]; then
    log_message "ERROR" "jamfHelper not found or not executable."
    echo "[ERROR] -- jamfHelper not found or not executable."
    exit 1
fi

#########################################################################################
# MAIN SCRIPT -- EDIT WITH CAUTION
#########################################################################################
# Define the functions used in this script.


# Function to read the StartCalendarInterval from LaunchDaemon
get_launchdaemon_intervals() {
    # Use PlistBuddy to extract the StartCalendarInterval values for both check times
	firstCheckHour=$(defaults read /Library/LaunchDaemons/com.aspeninstitute.reboot.plist StartCalendarInterval | grep -A 1 "Hour" | head -n 1 | awk '{print $3}' | tr -d ';')
	firstCheckMinute=$(defaults read /Library/LaunchDaemons/com.aspeninstitute.reboot.plist StartCalendarInterval | grep -A 1 "Minute" | head -n 1 | awk '{print $3}' | tr -d ';')
	secondCheckHour=$(defaults read /Library/LaunchDaemons/com.aspeninstitute.reboot.plist StartCalendarInterval | grep -A 1 "Hour" | tail -n 2 | head -n 1 | awk '{print $3}' | tr -d ';')
	secondCheckMinute=$(defaults read /Library/LaunchDaemons/com.aspeninstitute.reboot.plist StartCalendarInterval | grep -A 1 "Minute" | tail -n 2 | head -n 1 | awk '{print $3}' | tr -d ';')

    # Handle missing data
    if [ -z "$firstCheckHour" ] || [ -z "$secondCheckHour" ]; then
        log_message "ERROR" "Failed to retrieve check intervals from LaunchDaemon plist."
        exit 1
    fi

    echo "First check interval at $firstCheckHour:$firstCheckMinute, second check interval at $secondCheckHour:$secondCheckMinute"
    log_message "intervals" "First check at $firstCheckHour:$firstCheckMinute, second check at $secondCheckHour:$secondCheckMinute"
}

# Call the function to retrieve the first and second check times
get_launchdaemon_intervals

# Determine the current time in hours and minutes
currentHour=$(date +"%H")
currentMinute=$(date +"%M")
currentTotalMinutes=$((currentHour * 60 + currentMinute))

# Calculate the total time in minutes for first and second checks
firstCheckTotalMinutes=$((firstCheckHour * 60 + firstCheckMinute))
secondCheckTotalMinutes=$((secondCheckHour * 60 + secondCheckMinute))

# Adjust countdown based on current time
if [[ "$currentTotalMinutes" -lt "$secondCheckTotalMinutes" ]]; then
    log_message "countdown_adjustment" "Current time is before the second check interval."

    # Calculate the time left until the second check
    timeLeftUntilSecondCheck=$((secondCheckTotalMinutes - currentTotalMinutes))

    if [[ "$timeLeftUntilSecondCheck" -gt 0 ]]; then
        countdownTimer=$timeLeftUntilSecondCheck
        log_message "countdown_adjustment" "Countdown adjusted to $countdownTimer minutes (time left until the second check interval)."
    fi
else
    log_message "countdown_adjustment" "Current time is after the second check interval. Using the default 10-minute countdown."
    countdownTimer=10
fi

# Continue with the rest of the script (handling remainingDays, reboot warnings, etc.)
display_message() {
    log_message "display_message" "remaining days input as: $1"
    title="Reboot Reminder"
    heading=""
    content=""
    timeoutTimer=$((countdownTimer * 60))
    currentTime=$(date +"%H:%M")

    icon=$messageIcon
    title="Message from ITS"
    button1="Reboot Now"
    newline=$'\n'

    if [[ $1 -le 0 ]]; then
        if [[ $1 -lt 0 ]]; then
            # Immediate reboot with countdown
            log_message "display_message" "Immediate reboot due to negative remaining days ($1), countdown of $countdownTimer minutes."
            heading="Immediate Reboot Required"
            content="Your computer has exceeded its uptime limit and will reboot in $countdownTimer minutes. Please save your work."
            user_choice="$("$jamfHelper" -windowType utility -title "$title" -heading "$heading" -description "$content" -icon "$icon" -button1 "$button1" -defaultButton "1" -timeout "$timeoutTimer" -countdown -alignCountdown right)"
        elif [[ "$currentTime" > "$scheduledRebootTime" ]]; then
            log_message "display_message" "Current time is $currentTime and after scheduled reboot time ($scheduledRebootTime). Displaying reminder."
            heading="Reboot Required"
            content="Your computer must reboot now.${newline}Please save your work."
            user_choice="$("$jamfHelper" -windowType utility -title "$title" -heading "$heading" -description "$content" -icon "$icon" -button1 "$button1" -button2 "Defer $countdownTimer min" -defaultButton "1" -timeout "$timeoutTimer" -countdown -alignCountdown right)"
        else
            log_message "display_message" "Current time is before scheduled reboot time on the last deferral day. Delaying reminder."
            exit 0
        fi
    elif [[ $1 -eq 1 ]]; then
        log_message "display_message" "reported 1 day left before reboot"
        heading="Last Day Before Reboot"
        content="Today is the last day before your computer must reboot.${newline}Please save your work."
        user_choice="$("$jamfHelper" -windowType utility -title "$title" -heading "$heading" -description "$content" -icon "$icon" -button1 "$button1" -button2 "Defer" -defaultButton "1" -timeout "$timeoutTimer" -countdown -alignCountdown right)"
    elif [[ $1 -le $deferralLimit ]]; then
        log_message "display_message" "reported less than $deferralLimit day(s) left before reboot"
        heading="Reboot Required"
        content="Your computer must reboot every $uptimeLimit days.${newline}There are $remainingDays days remaining before the computer will reboot."
        user_choice="$("$jamfHelper" -windowType utility -title "$title" -heading "$heading" -description "$content" -icon "$icon" -button1 "$button1" -button2 "Defer" -defaultButton "2" -timeout "$timeoutTimer" -countdown -alignCountdown right)"
    else
        log_message "display_message" "reported more than the deferralLimit days left before reboot"
    fi
    echo "$user_choice"
}

# Function to display countdown window
display_countdown() {
	log_message "display_countdown" "displaying the countdown with $1 minutes"
	title="Message from ITS"
    heading="Reboot Reminder"
	newline=$'\n'
	timeoutTimer=$((countdownTimer * 60))

    content="Your computer will reboot in $1 minute(s).${newline}Please save your work.${newline}${newline}If you click \"Reboot Now\" below, your computer will reboot imediately."
    icon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"
	"$jamfHelper" -windowType utility -title "$title" -heading "$heading" -description "$content" -icon "$icon" -timeout "$timeoutTimer" -button1 "Reboot Now" -countdown -alignCountdown right -defaultButton 1 1> /dev/null
}

# Function to forcefully quit a process that did not gracefully shut down
kill_process() {
	log_message "kill_process" "kill invoked for $1"
    process="$1"
	if [ ! $testMode ]; then
		if /usr/bin/pgrep "$process" >/dev/null ; then 
			/usr/bin/pkill "$process" && log_message "kill_process" "$process ended" || \
			log_message "kill_process" "'$process' could not be killed"
		fi
	else
		if /usr/bin/pgrep "$process" >/dev/null ; then 
			log_message "TEST-kill_process" "$process ended"
		fi

	fi		
}

# Function to gracefully quit all open applications except excluded ones
graceful_quit() {
	log_message "graceful_quit" "function has been called."
	warnIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"
	errorIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"
	# Code pulled from: https://stackoverflow.com/questions/43289901/shell-script-for-closing-all-apps-open-dock-via-command-line
	# Creates a comma-separated String of open applications and assign it to the APPS variable.
	APPS=$(osascript -e 'tell application "System Events" to get name of (processes where background only is false)')

	# Convert the comma-separated String of open applications to an Array using IFS.
	# http://stackoverflow.com/questions/10586153/split-string-into-an-array-in-bash
	IFS=',' read -r -a myAppsArray <<< "$APPS"
	# Function to check if an element is in an array
	is_excluded() {
	    local app="$1"
		log_message "graceful_quit" "Doing exclusion check on $1"
	    for excluded in "${excluded_apps[@]}"; do
	        if [[ "$excluded" == "$app" ]]; then
			log_message "graceful_quit" "$app is excluded."
	            return 0
	        fi
	    done
	    log_message "graceful_quit" "$app is NOT excluded."
	    return 1
	}
	# Loop through each item in the 'myAppsArray' Array.
	for myApp in "${myAppsArray[@]}"
	do
	  # Remove space character from the start of the Array item
	  appName=$(echo "$myApp" | sed 's/^ *//g')

	  # Avoid closing the "Finder" and your CLI tool.
	  # Note: you may need to change "iTerm" to "Terminal"
	  if [[ "$appName" == "msupdate" ]]; then
      	log_message "graceful_quit" "Quitting: $appName"
      	if [ $testMode ]; then
			log_message "TESTING_MODE" "kill_process $appName"
		else
			kill_process "$appName"
		fi
      elif ! is_excluded "$appName"; then
        # quit the application
	    log_message "graceful_quit" "Quitting: $appName"
		if [ ! $testMode ]; then	    
			osascript -e 'quit app "'"$appName"'"'
			sleep 1
			if (ps aux | grep "$appName" | grep -v "grep" > /dev/null); then
				log_message "graceful_quit" "$appName did not quit. Requesting permission to force quit the app."
	
				# Use JamfHelper to tell the user what happened.
				confirmation=$("$jamfHelper" -windowType utility -title "$appName didn't quit" -icon $warnIcon -description "We were unable to close $appName. May we force the app to quit?" -button1 "Cancel" -button2 "Okay" -cancelButton 1 -defaultButton 2 2> /dev/null)
				buttonClicked="${confirmation:$i-1}"
				if [[ "$buttonClicked" == "0" ]]; then
					log_message "graceful_quit" "User DECLINED forcequit"
					log_message "graceful_quit" "This is where we would normally exit."
	#            	exit 0
				elif [[ "$buttonClicked" == "2" ]]; then
					log_message "graceful_quit" "User CONFIRMED forcequit"
					kill_process "$appName"
				else
					log_message "graceful_quit" "User FAILED to confirm forcequit"
					exit 1
				fi
			fi
		else
			log_message "TESTING_MODE" "graceful_quit $appName (unable to properly test this, so skipping ahead.)"
		fi
	  fi
	done
}

# Display the user message and do the uptime checks
user_choice=$(display_message $remainingDays)

# Handle user choice
case $user_choice in
    "0")
        echo "Rebooting..."
        display_countdown $countdownTimer
        
        if [ ! -z $testUptime ]; then
            log_message "TESTING_MODE" "Skipping graceful_quit due to testing mode."
        else
            graceful_quit
        fi
        
        if [ ! -z $testUptime ]; then
            log_message "TESTING_MODE" "sudo shutdown -r now"
        else
            echo "[reboot] -- Rebooting computer now with: sudo shutdown -r now"
            sudo shutdown -r now
        fi         
        ;;
    "2")
        if [[ $remainingDays -le 0 ]]; then
            display_countdown $countdownTimer
            
            if [ ! -z $testUptime ]; then
                log_message "TESTING_MODE" "Skipping graceful_quit due to testing mode."
            else
                graceful_quit
            fi
            
            log_message "user_choice" "Deferring reboot for $countdownTimer""min."
            echo "[user_choice] -- Deferring reboot for $countdownTimer""min."
            
            if [ ! -z $testUptime ]; then
                log_message "TESTING_MODE" "sudo shutdown -r now"
            else
                echo "[user_choice] -- Rebooting now."
                sudo shutdown -r now
            fi        
        else
            log_message "user_choice" "Deferring reboot for another day."
            echo "[user_choice] -- Deferring reboot for another day."
            # Add your deferral logic here
        fi
        ;;
    *)
        log_message "user_choice" "Invalid choice."
        echo "[user_choice] -- Could not decipher user reboot choice."
        ;;
esac

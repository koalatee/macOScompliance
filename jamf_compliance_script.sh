#!/bin/bash 
# jjourney / @koalatee 01/2018

### compliance reporting check:
# - macOS operating system version
#    - smart group (set by IT/security - full build e.g. 10.12.6)
# - encryption status
#    - smart group / as desired
# - Software Updates Available in App Store

### Later goal (or second project)
# - Application version checks (maybe in conjunction with patch policies)

######################## Readme ########################
# Check readme on front page: https://github.com/koalatee/macOScompliance
# For use with jamf 
# jamf requirements:
# - api account with READ access to 'Patch Reporting Software Titles'
#   - update the salt and passphrase below
#   - see https://github.com/jamfit/Encrypted-Script-Parameters for more information
# Required smart groups:
# - Operating System like {full OS version} (e.g. 10.12.6)
# - Has software updates available (whether )
# - encryption status
#   - update smart group IDs below
# - compliance fail = member of any of the above groups
# Required policies with custom triggers (for use with parameter 8-11):
# - re-key Filevault
#   - personally using https://github.com/homebysix/jss-filevault-reissue
# - macOS installer 
#   - personally using https://github.com/bp88/JSS-Scripts/blob/master/OS_Upgrade.sh 
# - run software updates
#   - personally using jamf built-in software update
# - start encryption
#   - update triggers below
# Update it_contact
# Update jamfURL with your jamf url (e.g. https://yourjamf.com:8443)
# Update macos_upgrade_message if you don't want it to say "backup to Dropbox"
# 
### Script parameters: ###
# (Required)
# 04: api account username encrypted string
# 05: api account password encrypted string
# 06: full macOS version to check (e.g. 10.12.6) 
#   - should correspond with the smart group
# 07: 
# 08: jamf custom trigger for filevault rekey
# 09: jamf custom trigger for macOS installer
# 10: jamf custom trigger for software updates
# 11: jamf custom trigger for encryption Policy
#
# Exit Codes
# 00: machine running updates or is now compliant
# 02: error with parameters
# 03: API error
# 04: user is not in fv users
# 06: machine error with filevault status
# 07: machine error with macOS version
# 08: machine error with software updates
# 09: machine is not compliant and user opted to fix themselves
######################## End Readme ########################

##### Variables #####
# editable
jamfURL="https://your.jamf.here:8443" # <--- update here
it_contact="IT" # <--- update here

## jamf smart group ID numbers
# editable
sg_Full_OS= # <--- update here
sg_software= # <--- update here
sg_encryption= # <--- update here

## Display name for array and user, recommend no spaces
# editable
array_macOS="macOS"
array_software="software"
array_encryption="encryption" 

## Function for api account string decryption
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}
## Decrypt username + password
# edit salt and passphrase
apiUser=$(DecryptString $4 '$apiUserSalt' '$apiUserPassphrase') # <--- update here
apiPass=$(DecryptString $5 '$apiPassSalt' '$apiPassPassphrase') # <--- update here

##### jamf Script Parameters #####
## Do not edit
req_os="${6}"
req_os_maj="$(/bin/echo "$req_os" | /usr/bin/cut -d . -f 2)"
req_os_min="$(/bin/echo "$req_os" | /usr/bin/cut -d . -f 3)"

trigger_filevault_rekey="${8}"
trigger_macOS_installer="${9}"
trigger_software_updates="${10}"
trigger_encryption="${11}"
## Local variables to determine paths, OS version, disk space, udid, and power connection
# Do not edit     
local_os="$(/usr/bin/sw_vers -productVersion)"
local_os_maj="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d . -f 2)"
local_os_min="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d . -f 3)"
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
jamf="/usr/local/bin/jamf"
serialNumber="$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')"
logged_in_user="$(/usr/bin/python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");')"
## icons
# editable
filevaulticon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns"
complianticon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/com.apple.macbook-retina-space-gray.icns"
noncomplianticon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"
manualfixicon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"
downloadicon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericNetworkIcon.icns"
## Messages to users
# editable
filevault_user_error="You are not a member of the Filevault users. Please contact $it_contact for assistance in resolving."
mac_now_compliant="Your machine is now compliant."
generic_error="An unexpected error has occurred. Please contact $it_contact."
logout_message="Save all open work. Press Log Out to immediately logout and start encryption"
software_upgrade_message="Downloading and installing software updates from Apple. When ready to install, a restart message will pop-up."
manualfix_message="Check Software Center (under the update category) to resolve compliance issues. If you have any questions, contact $it_contact"
macos_upgrade_message="Running installer for macOS updater. This will upgrade your Mac to macOS $req_os. 
Before proceeding:
- Please ensure *all work is saved* - important documents and files should be saved to Dropbox. 
- Contact $it_contact with any questions on backing up.
- Close any apps you may have open.
- This process will take 45 minutes to complete, during which time you will *not* be able to use your Mac"
##### End Variables #####

# Make sure all parameters are setup
checkParam (){
if [[ -z "$1" ]]; then
    /bin/echo "\$$2 is empty and required. Please fill in the JSS parameter correctly."
    "$jamfHelper" \
        -windowType utility \
        -icon "$alerticon" \
        -heading "Error" \
        -description "$generic_error" \
        -button1 "Exit" \
        -defaultButton 1 &
    exit 2
fi
}

checkParam "$trigger_filevault_rekey" "trigger_filevault_rekey"
checkParam "$trigger_macOS_installer" "trigger_macOS_installer"
checkParam "$trigger_software_updates" "trigger_software_updates"
checkParam "$trigger_encryption" "trigger_encryption"

# Exit cleanup (if a machine only needs to start encryption)
function cleanup()
{
    ## Logs out and prompts for filevault
    launchctl bootout gui/$(id -u $logged_in_user)
}

# Check smart group to see if a member
# run as SmartGroupCheck "$display_name" "$sg_id_variable"
# $display_name is added to an array to determine/double-check what is out of date

function SmartGroupCheck () {
    smartCheck="$(curl \
        -s \
        -f \
        -u ${apiUser}:${apiPass} \
        -X GET $jamfURL/JSSResource/computergroups/id/"${2}" \
        -H "Accept: application/xml" \
        | xpath "/computer_group/computers/computer[serial_number = '$serialNumber']"
    )"
    if [ -z "$smartCheck" ]; then
        echo "Not a member of the "${1}" group."
        sg_groups_passed+=("${1}")
    elif [[ "$smartCheck" =~ "$serialNumber" ]]; then
        echo "Member of the "${1}" group."
        sg_groups_failed+=("${1}")
    else 
        echo "Some error occured."
        exit 3
    fi
}

# Check for all groups
SmartGroupCheck $array_encryption $sg_encryption
SmartGroupCheck $array_macOS $sg_Full_OS
SmartGroupCheck $array_software $sg_software

echo "Machine smart groups passed: "${sg_groups_passed[@]}""
echo "Machine smart groups failed: "${sg_groups_failed[@]}""

### Filevault checks
# Check to see if the encryption process is complete
FV_STATUS="$(/usr/bin/fdesetup status)"
if [[ "$FV_STATUS" =~ "FileVault is On" ]]; then
        /bin/echo "$FV_STATUS"
        /bin/echo "Filevault is On."
        local_groups_passed+=($array_encryption)
    elif [[ "$FV_STATUS" =~ "FileVault is Off" ]]; then
        /bin/echo "Encryption is not active."
        /bin/echo "$FV_STATUS"
        local_groups_failed+=($array_encryption)    
    elif [[ "$FV_STATUS" =~ "Encryption in progress" ]]; then
        /bin/echo "$FV_STATUS"
        /bin/echo "Filevault is encrypting."
        local_groups_passed+=($array_encryption)
    elif [[ ! "$FV_STATUS" =~ "FileVault is On" ]]; then
        /bin/echo "Unable to determine encryption status."
        /bin/echo "$FV_STATUS"
        exit 6
fi

### macOS checks
# Check current macOS version against required version
if [ $local_os = $req_os ]; then
        /bin/echo "macOS version is up-to-date"
        /bin/echo "Mac running $local_os"
        local_groups_passed+=($array_macOS)
    elif [ $local_os_maj -gt $req_os_maj ]; then
        /bin/echo "Mac on higher version than required."
        /bin/echo "Mac running $local_os"
        local_groups_passed+=($array_macOS)
    elif [ $local_os_maj -eq $req_os_maj ] && [ ! $local_os_min -eq $req_os_min ]; then
        /bin/echo "Major version up-to-date, minor version out-of-date. Run software update"
        /bin/echo "Mac running $local_os"
        local_groups_passed+=($array_macOS)
    elif [ ! $local_os_maj -eq $req_os_maj ]; then
        /bin/echo "Major version out of date. Run complete macOS update"
        /bin/echo "Mac running $local_os"
        local_groups_failed+=($array_macOS)
    else
        /bin/echo "Unknown error with $array_macOS"
        /bin/echo "Mac running $local_os"
        exit 7
fi

### software update checks
local_su="$(defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastUpdatesAvailable)"
if [ $local_su = 0 ]; then
        /bin/echo "Mac has no updates available"
        local_groups_passed+=($array_software)
    elif [ $local_su -gt 0 ]; then
        /bin/echo "Mac has $local_su updates available"
        local_groups_failed+=($array_software)
    else 
        /bin/echo "Unknown error with $array_software"
        exit 8
fi

echo "Local machine passed: "${local_groups_passed[@]}""
echo "Local machine failed: "${local_groups_failed[@]}""
# For jamfHelper description fixes
local_groups_fail=$(echo ${local_groups_failed[@]} |sed -e 's/ /, /g')
local_groups_pass=$(echo ${local_groups_passed[@]} |sed -e 's/ /, /g')

# This first user check sees if the logged in account is already authorized with FileVault 2
# re-keys filevault key before continuing
fv_users="$(/usr/bin/fdesetup list)"
if [[ ${local_groups_passed[@]} =~ $array_encryption ]]; then
    if ! egrep -q "^${logged_in_user}," <<< "$fv_users"; then
        /bin/echo "$logged_in_user is not on the list of FileVault enabled users:"
        /bin/echo "$fv_users"
        "$jamfHelper" \
            -windowType utility \
            -icon "$filevaulticon" \
            -heading "FileVault Error" \
            -description "$filevault_user_error" \
            -button1 "Exit" \
            -defaultButton 1 &
        exit 4
    else 
        /bin/echo "running FileVault rekey"
        $jamf policy -event $trigger_filevault_rekey
        sleep 10
    fi
fi

### Display to users what they passed, what they didn't
# If machine is compliant, but some backend error exists
if [[ -z ${local_groups_failed[@]} ]]; then
        # Computer not in smart groups and local is fine (error)
        /bin/echo "Compliant on mac, fixing in jamf with inventory update."
        $jamf recon &
        "$jamfHelper" \
            -windowType utility \
            -icon "$complianticon" \
            -description "$mac_now_compliant." \
            -heading "Compliant" \
            -button1 "Exit" \
            -defaultButton 1 &
        exit 0
fi

# If machine is not compliant, failed a local check
if [[ ! -z ${local_groups_failed[@]} ]]; then
    # jamfHelper exit codes
    # https://gist.github.com/homebysix/18c1a07a284089e7f279
    # 2 is button2 - 'fix manually'
    # 0 is button1 - 'fix now'
    if [[ -z ${local_groups_passed[@]} ]]; then
        userChoose="$("$jamfHelper" \
            -windowType utility \
            -icon "$noncomplianticon" \
            -description "Your mac has failed compliance in all areas: $local_groups_fail. You can fix now or fix manually. All updates will require a restart and may take some time." \
            -heading "Non Compliant Mac" \
            -button1 "Fix now" \
            -button2 "Fix manually" \
            -defaultButton 1 )"
    else 
        userChoose="$("$jamfHelper" \
            -windowType utility \
            -icon "$noncomplianticon" \
            -description "Your mac is compliant with $local_groups_pass, but does not meet compliance with $local_groups_fail. You can fix now or fix manually. All updates will require a restart and may take some time." \
            -heading "Non Compliant Mac" \
            -button1 "Fix now" \
            -button2 "Fix manually" \
            -defaultButton 1 )"
    fi
    if [ $userChoose = 2 ]; then
        "$jamfHelper" \
            -windowType utility \
            -icon "$manualfixicon" \
            -description "$manualfix_message" \
            -heading "Manual Fix" \
            -button1 "OK" \
            -defaultButton 1 &
        exit 9
    fi
fi

# User has opted to fix now
if [ $userChoose = 0 ]; then
    /bin/echo "Fixing compliance issues with: ${local_groups_failed[@]}"
    if [[ ${local_groups_failed[@]} =~ $array_encryption ]]; then
        /bin/echo "Running jamf trigger for $array_encryption."
        $jamf policy -event $trigger_encryption
    fi
    if [[ ${local_groups_passed[@]} =~ $array_macOS ]] && [[ ${local_groups_failed[@]} =~ $array_software ]]; then
        /bin/echo "Running jamf trigger for $array_software."
        "$jamfHelper" \
            -windowType utility \
            -icon "$downloadicon" \
            -description "$software_upgrade_message" \
            -heading "Software Updates" \
            -button1 "OK" \
            -defaultButton 1 &
        $jamf policy -event $trigger_software_updates 
        exit 0
    elif [[ ${local_groups_failed[@]} =~ $array_macOS ]]; then
        /bin/echo "Running jamf trigger for $array_macOS."
        /bin/echo "$array_software updates may need to be run after the installer."
        "$jamfHelper" \
            -windowType utility \
            -icon "$manualfixicon" \
            -description "$macos_upgrade_message" \
            -heading "Upgrade macOS" \
            -button1 "OK" \
            -defaultButton 1 
        $jamf policy -event $trigger_macOS_installer &
        exit 0
    fi
    "$jamfHelper" \
        -windowType utility \
        -icon "$noncomplianticon" \
        -description "$logout_message" \
        -heading "Warning: Save all Work!" \
        -button1 "Log Out" \
        -defaultButton 1
    trap cleanup EXIT
fi

exit 0

# macOS compliance
Compliance check for macOS.

This was written to help with some compliance. (wow, so descriptive)

## What does this do?
If a mac is a member of any of the smart groups (not on the $company approved macOS version, has macOS software updates, is not encrypted, does not have antivirus installed) they will see this policy.
This script double-checks which smart group this computer is a part of, and checks locally if it should be in those smart groups (to ensure accuracy) and acts accordingly.

<i>e.g. If a user is encrypted, but is on an old version of macOS and has software updates, they'll be prompted to upgrade macOS. If a user is on a current version (major) of macOS but is not encrypted and requires software updates, encryption will trigger and software updates will be run.</i>

## Requirements:

### 1. jamf
¯\\\_(ツ)\_/¯

### 2. jamf account for the API:
This account needs READ access to Smart Groups.
Use https://github.com/jamfit/Encrypted-Script-Parameters for more information on encrypted string parameters.

<i>Note, this is used for error-checking in case a user's machine is compliant but they are still in the smart groups that tell them they're not compliant. This may happen if you have infrequent inventory or other policies that run on a schedule that you want to bypass.</i>

### 3. Smart Groups:
1. Operating System {like} $full_os_version - you can set the macOS version you want to be 'compliant' (e.g. 10.14.6) - this should equal the version in your macOS upgrade policy.
2. Has Software Updates available - either use an EA or jamf built-in.
3. Machine not encrypted - use your discretion on the best way to check this. I use https://github.com/koalatee/scripts/blob/master/jamf/EAs/EA-AccurateFilevaultReporting.zsh to set an EA that is used for Smart Groups.
4. Machine does not have antivirus installed. 
4. Scope this script to Computer Group {member of} $above_group1 [or] Computer Group {member of} $above_group2 [or] Computer Group {member of} $above_group3 [or] Computer Group {member of} $above_group4.

<i>Note the ids of the first 4, as they are needed for the script. 
You can find these in the url - https://your.jamf.here:8443/smartComputerGroups.html?<b>id=64</b>&o=r&nav=null</i>

### 4. Policies (with custom triggers):
1. Rotate / re-key FileVault key - personally using https://github.com/koalatee/newFileVaultKey
2. macOS upgrade - personally using https://github.com/bp88/JSS-Scripts/blob/master/OS_Upgrade.sh
3. Run software updates - personally using command "softwareupdate -iaR"
4. Start encryption - recommend policy that enforces on next login
5. Install antivirus

## Script Setup:
1. Load script into jamf.
2. Update the following values (required):
- jamfURL
- it_contact
- smart group IDs (sg_Full_OS, sg_encryption, sg_encryption, sg_antivirus)
- apiUser salt and passphrase
- apiPass salt and passphrase
3. Update the following values/variables (optional):
- Messages to users - by default, macos_upgrade_message recommends backing up to Dropbox. Change if using a different service/method.
- Display name for array (array_macOS, array_encryption, array_software, array_antivirus). These names also display to the user - <i>"your machine is/not compliant with $array_macOS, $array_encryption, $array_software, $array_antivirus.</i>
4. Under the script options, change the display names for the parameters:
- Parameter 04 = apiUser encrypted string
- Parameter 05 = apiPass encrypted string
- Parameter 06 = macOS version to check (e.g. 10.12.6) - <i>as required by $company</i>
- Parameter 07 = antivirus install trigger
- Parameter 08 = FileVault re-key trigger
- Parameter 09 = macOS upgrade trigger
- Parameter 10 = software update installer trigger
- Parameter 11 = encryption trigger

## Policy setup
1. Create new policy with the script.
2. Fill in the script parameters as noted.
3. Scope to Smart Group 5.

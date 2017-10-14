#!/bin/sh

# onboarding.sh
# Authors: Kyle Brewer (with much inspiration from Mike Bombich)
# https://github.com/kylebrewer/macos-management
#
# Define hostname, join to Active Directory, define user accounts and local
# administrator group membership, and more.

### Confirm elevated permissions

# We need to execute as root to get some of this done.
# If the executing user is not root, the script will exit with code 1.
if [[ "$USER" != "root" ]]; then
	printf '\e[0;31mYou are attempting to execute this process as user \e[0;33m'$USER'\e[0;31m.\e[0m'
	printf '\n\e[0;31mPlease execute the script with elevated permissions.\e[0m\n'
	exit 1

fi

### Standard parameters

# Fully-qualified DNS name of Active Directory domain.
domain="ad.example.com"

# Distinguished name of intended container for this computer.
ou="CN=Computers,DC=ad,DC=example,DC=com"

# Hostname of LDAP server.
ldapserver="ldap.example.com"

# LDAP user. Requires read-only permissions for user queries.
ldapuser="ldapuser@ad.example.com"

# Hostname of NTP server. Used to synchronize clocks.
networktimeserver="time.example.com"


### Advanced options

# "enable" or "disable" automatic multi-domain authentication.
alldomains="enable"

# "enable" or "disable" force home directory to local disk.
localhome="enable"

# "afp" or "smb" change how home filesystem is mounted from server.
protocol="smb"

# "enable" or "disable" mobile account support for caching accounts.
# This allows a domain-based account to login when the client is offline.
mobile="enable"

# "enable" or "disable" warn operator that a mobile account will be created.
mobileconfirm="disable"

# "enable" or "disable" use AD SMBHome attribute to define user home directory.
useuncpath="disable"

# Define default shell. e.g., "/bin/bash" or "none".
user_shell="/bin/bash"

# Use the specified server for all directory lookups and authentication.
# (e.g. "-nopreferred" or "-preferred ad.example.com")
#preferred="-nopreferred"
preferred="ad.example.com"

# Enable or disable OpenSSH Server. If you enable sshd, consider hardening
# your configuration to prevent root login, etc.
# "enable" or "disable"
sshd_status="enable"

# Create a path to store your organization's support scripts.
# "yes" or "no"
support_script="yes"
# Define path. For example: /usr/local/supportscripts
support_script_path="/usr/local/supportscripts"

### End of configuration


### Begin functions

function sitelocation()
{
	# To support site-based naming convention, we need to guess the physical
	# location of the client by detecting the current IP address.
	# Note that grep -v inverts matching to ignore the loopback address.
	# In the case of multiple IP addresses, head will return only the first.
	ip=$(/sbin/ifconfig | /usr/bin/grep "inet " | /usr/bin/grep -v 127.0.0.1 | /usr/bin/cut -d\  -f2 | /usr/bin/head -n 1)

	# Evaluate IP address against known subnets to define site-specific
	# configuration of hostnames, AD OUs, and AD administrator groups.
	# Unknown locations will default to Example Corp. HQ values.

	# Assuming Example Corp. HQ has the most clients. Start here to reduce the
	# complexity of our evaluation.

	#Example Corp. HQ site 00
	if [[ $ip =~ ^10\.30\. ]] || \
	[[ $ip =~ ^10\.31\. ]]; then
		siteprefix="s00"
		#ou="OU=Workstations,OU=site 00,DC=ad,DC=example,DC=com"
		admingroups="EXAMPLE\Domain Admins,EXAMPLE\NetworkAdmins,EXAMPLE\s00-DesktopAdmins"

	#Example Corp. satellite site 01
	elif [[ $ip =~ ^10\.104\.[0-1]{1}\. ]] || \
	[[ $ip =~ ^10\.104\.9\. ]] || \
	[[ $ip =~ ^10\.104\.1[0-2]{1}\. ]]; then
		siteprefix="s01"
		#ou="OU=Workstations,OU=site 01,DC=ad,DC=example,DC=com"
		admingroups="EXAMPLE\Domain Admins,EXAMPLE\NetworkAdmins,EXAMPLE\s01-DesktopAdmins"

	# Unknown site.  Default to Example Corp HQ site 00 values.
	else
		siteprefix="s00"
		#ou="OU=Workstations,OU=site 00,DC=ad,DC=example,DC=com"
		admingroups="EXAMPLE\Domain Admins,EXAMPLE\NetworkAdmins,EXAMPLE\s00-DesktopAdmins"

	fi

}


function bind()
{
	# Authenticate with privileged AD credentials (probably YOURS!).
	printf '\n\e[0;31mManipulating AD objects requires privileged credentials.\e[0m\n'
	printf '\n\e[0;31mPrompting for your AD credentials.\e[0m\n'

	# Here we'll ask for a privileged AD username.
	read -p $'\e[0;31mEnter your AD username:\e[0m ' domainadmin

	# And here we'll ask for the password of the privileged AD username.
	read -s -p $'\e[0;31mEnter your AD password:\e[0m ' password

	# Query current AD relationship, if available.
	# If client is currently bound, attempt force unbind, then bind.
	# If "dsconfigad -show" returns nothing, client is not currently bound.
	if [ ! "$(/usr/sbin/dsconfigad -show)" = "" ]; then
		# Currently bound to object. Force unbind before proceeding.
		boundname=$(/usr/sbin/dsconfigad -show | /usr/bin/awk -F\= '/Computer Account/{gsub(/ /, "");gsub(/\$/, ""); print $(NF)}')
		echo "\n\nAlready bound to object $boundname. Attempting to force unbind."
		/usr/sbin/dsconfigad -f -r $boundname -u $domainadmin -p $password

	fi

	# Before we define the NTP server, we should test for the presence of /etc/ntp.conf
	if [ ! -f /etc/ntp.conf ]; then
		/usr/bin/touch /etc/ntp.conf

	fi

	# Define NTP server.
	echo "\n\nConfiguring NTP."
	/usr/sbin/systemsetup setnetworktimeserver $networktimeserver > /dev/null 2>&1


	# Activate the AD plugin by updating DirectoryService preferences.
	echo "\nUpdating DirectoryService preferences to activate AD plugin."
	/usr/bin/defaults write /Library/Preferences/DirectoryService/DirectoryService "Active Directory" "Active"

	# Now we wait a few seconds to allow the Active Directory plugin to start.
	#echo "Waiting 5 seconds to let DirectoryService framework start."
	/bin/sleep 5


	# Truncated hardware serial. Collect last 7 characters of serial to match Dell service tag standard.
	truncserial=$(/usr/sbin/ioreg -c IOPlatformExpertDevice -d 2 | /usr/bin/awk -F\" '/IOPlatformSerialNumber/{print tolower(substr($(NF-1),1+length($(NF-1))-7))}')

	# Combine $siteprefix and $truncserial for a standard hostname.
	localhostname=$siteprefix-$truncserial

	# Set HostName, LocalHostName, ComputerName, using value assigned in $localhostname.
	echo "\nConfiguring HostName, LocalHostName, and ComputerName as $localhostname."
	/usr/sbin/scutil --set HostName $localhostname
	/usr/sbin/scutil --set LocalHostName $localhostname
	/usr/sbin/scutil --set ComputerName $localhostname

	# Bind to domain object with hostname defined above, and place
	# in appropriate AD organizational unit.
	echo "\nBinding computer to $domain as $localhostname."
	/usr/sbin/dsconfigad -f -a $localhostname -domain $domain -u $domainadmin -p "$password" -ou "$ou"

	# Define local admin groups, to be listed in Directory Utility.
	# If no groups are defined in $admingroups, -nogroups option is used.
	if [ "$admingroups" = "" ]; then
		/usr/sbin/dsconfigad -nogroups
	else
		echo "\nConfiguring AD Groups with local admin privileges."
		/usr/sbin/dsconfigad -groups "$admingroups"
	fi

	echo "\nConfiguring mobile settings."
	/usr/sbin/dsconfigad -alldomains $alldomains -localhome $localhome -protocol $protocol -mobile $mobile -mobileconfirm $mobileconfirm -useuncpath $useuncpath -shell $user_shell -preferred $preferred

}


function forceunbind()
{
	# Force unbind from domain object.
	# If "dsconfigad -show" returns nothing, client is not currently bound.
	if [ ! "$(/usr/sbin/dsconfigad -show)" = "" ]; then
		# Currently bound to object. Force unbind before proceeding.
		boundname=$(/usr/sbin/dsconfigad -show | /usr/bin/awk -F\= '/Computer Account/{gsub(/ /, "");gsub(/\$/, ""); print $(NF)}')
		echo "\nAlready bound to object $boundname. Attempting to force unbind."
		/usr/sbin/dsconfigad -f -r $boundname -u $domainadmin -p $password
	else
		echo "\nNo bound object found."

	fi

}


function configure()
{
	# Standard configuration of services.
	# Enable or disable OpenSSH Server. If this is not explicitly enabled
	# in the configuration above, we'll disable sshd and reduce the attack
	# surface.
	if [[ "$sshd_status" = "enable" ]]; then
		if [[ ! $(/usr/sbin/systemsetup -getremotelogin) =~ "On" ]]; then
			echo "\nSSH server was disabled. Enabling SSH server."
			/usr/sbin/systemsetup -setremotelogin on

		fi

	else
			/usr/sbin/systemsetup -setremotelogin off

	fi

	# Create directory for Example Corp's standard support scripts.
	if [[ "$support_script" = "yes" ]]; then
		if [[ ! -d "$support_script_path" ]]; then
			/bin/mkdir -p $support_script_path
			/usr/sbin/chown root: $support_script_path
			/bin/chmod 0555 $support_script_path

		fi

	fi

}


function users()
{
	# Prompt for end-user local admin(s).
	printf '\n\e[0;31mEnter the AD usernames of the associates who require local administrator privileges.\e[0m'
	read -p $'\n\e[0;31mYou MUST separate multiple usernames with spaces: \e[0m' localadmins

	# Iterate through each username in @localadmins array to provision each user account.
	for username in ${localadmins[@]}
	do
		# Confirm provided account names do not exist locally.
		# To manually remove a user account:
		# dscl . -delete "/Users/<username>"
		# Note: that method does not delete the user's non-primary group memberships.
		if [[ ! "$(/usr/bin/dscl . -list /Users | /usr/bin/grep $username)" = "" ]]; then
			printf '\n\e[0;31mAccount \e[0;33m'$username'\e[0;31m already exists locally.\e[0m'
			pause
			return 1

		fi

		# Here we'll query LDAP for information about any users specified in @localadmins.
		uid=$(/usr/bin/ldapsearch -x -LLL -H ldaps://$ldapserver -b dc=ad,dc=example,dc=com -D $ldapuser -w readonly "(samaccountname=$username)" uidnumber | /usr/bin/awk -F\: '/^uidNumber/{gsub(/^[ \t]/, "", $(NF)); print $(NF)}')
		displayname=$(/usr/bin/ldapsearch -x -LLL -H ldaps://$ldapserver -b dc=ad,dc=example,dc=com -D $ldapuser -w readonly "(samaccountname=$username)" displayname | /usr/bin/awk -F\: '/^displayName/{gsub(/^[ \t]/, "", $(NF)); print $(NF)}')
		displaynameprintable=$(/usr/bin/ldapsearch -x -LLL -H ldaps://$ldapserver -b dc=ad,dc=example,dc=com -D $ldapuser -w readonly "(samaccountname=$username)" displaynameprintable | /usr/bin/awk -F\: '/^displayNamePrintable/{gsub(/^[ \t]/, "", $(NF)); print $(NF)}')
		title=$(/usr/bin/ldapsearch -x -LLL -H ldaps://$ldapserver -b dc=ad,dc=example,dc=com -D $ldapuser -w readonly "(samaccountname=$username)" title | /usr/bin/awk -F\: '/^title/{gsub(/^[ \t]/, "", $(NF)); print $(NF)}')
		department=$(/usr/bin/ldapsearch -x -LLL -H ldaps://$ldapserver -b dc=ad,dc=example,dc=com -D $ldapuser -w readonly "(samaccountname=$username)" department | /usr/bin/awk -F\: '/^department/{gsub(/^[ \t]/, "", $(NF)); print $(NF)}')
		location=$(/usr/bin/ldapsearch -x -LLL -H ldaps://$ldapserver -b dc=ad,dc=example,dc=com -D $ldapuser -w readonly "(samaccountname=$username)" l | /usr/bin/awk -F\: '/^l:/{gsub(/^[ \t]/, "", $(NF)); print $(NF)}')

		# Prompt operator to confirm intended user.
		# Test for different account types and shape operator prompt.
		if [[ $title == *Contractor* ]] || [[ $title  == *Consultant* ]]; then
			# Title contains "Contractor" or "Consultant".
			printf '\n\e[0;31mYou have selected contractor/consultant:\e[0m'
			echo "\n\t$displaynameprintable\n\t$title\n\t$department\n\t$location\n"
			printf '\n\e[0;31mConsider the risk in providing this user administrator privileges.\e[0m'
			read -p $'\n\e[31mIs this the correct user? [\e[33my\e[31m/\e[33mN\e[31m]\e[0m ' response

		elif [[ -n $displaynameprintable ]]; then
			# displayNamePrintable field has a nonzero length. Individual user.
			printf '\n\e[0;31mYou have selected associate:\e[0m'
			echo "\n\t$displaynameprintable\n\t$title\n\t$department\n\t$location\n"
			read -p $'\e[31mIs this the correct user? [\e[33my\e[31m/\e[33mN\e[31m]\e[0m ' response

		elif [[ -n $displayname ]]; then
			# displayNamePrintable field has zero length. Generic account.
			printf '\n\e[0;31mYou have selected generic account:\e[0m'
			echo "\n\t$displayname\n"
			read -p $'\e[31mIs this the correct user? [\e[33my\e[31m/\e[33mN\e[31m]\e[0m ' response

		else
			# Operator-provided username not found in LDAP. Invalid username.
			printf '\n\e[0;31mUsername \e[0;33m'$username'\e[0;33m not found in LDAP.\e[0m'
			printf '\n\e[0;31mPlease confirm the username and account status and try again.\e[0m'
			pause
			return 1

		fi

		# Evaluate operator response. Only "y" or "Y" will indicate the correct user.
		# Otherwise, the script will exit without making any changes.
		if [[ $response == y ]] || [[ $response == Y ]]; then
			# Create mobile account for user(s) specified in @localadmins.
			# Domain groups inherited as expected, i.e., members of EXAMPLE\s??-DesktopAdmins are admins.
			# Note: this will pass two odd messages to the CLI, this is a known bug in ManagedClient.
			echo "\nCreating account for user $username."
			# This command may output two debug messages that do not indicate errors.
			# For that reason, we silence output with a redirect.
			/System/Library/CoreServices/ManagedClient.app/Contents/Resources/createmobileaccount -n "$username" > /dev/null 2>&1

			# Add username(s) specified in @localadmins to local admin group.
			# dscl will allow a local group's membership to contain multiple instances of the same username.
			# As this can cause confusion, we will query the group prior to granting membership.
			if [[ "$(/usr/bin/dscl . -read /Groups/admin GroupMembership | /usr/bin/grep $username)" == "" ]]; then
				# User is not a member of the local admin group. Grant membership.
				echo "\nAdding user $username to local admin group."
				/usr/bin/dscl . -append /Groups/admin GroupMembership "$username"

			else
				# User is already a member of the local admin group. Make no changes.
				# To manually remove a user from a local group:
				# dseditgroup -o edit -d <username> -t user <group>
				echo "User $username is already a member of the local admin group."

			fi
		else
			# Invalid or negative response.
			printf '\n\e[0;31mPlease confirm the username and try again.\e[0m'
			pause
			return 1

		fi

	done

}


function summary()
{
	# Sanity check. Rather than printing from variables, we'll query the system configuration for these values.
	echo "\n*** SUMMARY ***"
	echo "Hardware serial number:"
	/usr/sbin/ioreg -c IOPlatformExpertDevice -d 2 | /usr/bin/awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}'

	echo "\nHostname:"
	/usr/sbin/scutil --get HostName

	# Print AD forest.
	echo "\nActive Directory forest:"
	/usr/sbin/dsconfigad -show | /usr/bin/awk -F\= '/^Active Directory Forest/{gsub(/ /, ""); print $(NF)}'

	# Print AD domain, specified in $domain variable.
	echo "\nActive Directory domain:"
	/usr/sbin/dsconfigad -show | /usr/bin/awk -F\= '/^Active Directory Domain/{gsub(/ /, ""); print $(NF)}'

	# Print preferred domain controller, specified in $preferred variable.
	echo "\nPreferred domain controller:"
	/usr/sbin/dsconfigad -show | /usr/bin/awk -F\= '/Preferred Domain controller/{gsub(/ /, ""); print $(NF)}'

	# Print network time server and ntpd status.
	echo "\nNetwork time server:"
	/usr/sbin/systemsetup getnetworktimeserver | /usr/bin/awk '{print $(NF)}'
	echo "\nNetwork time status:"
	/usr/sbin/systemsetup getusingnetworktime | /usr/bin/awk '{print $(NF)}'

	# Print members of local "admin" group.
	echo "\nCurrent members of local \"admin\" group:"
	/usr/bin/dscl . -read /Groups/admin GroupMembership | /usr/bin/awk -F ' ' '{for (i=2; i<=NF; i++) print $i}'

	# Print allowed admin groups, specified in $admingroups variable.
	echo "\nAllowed admin groups:"
	/usr/sbin/dsconfigad -show | /usr/bin/grep "Allowed admin groups" | /usr/bin/sed -e $'s/.*= //;s/,/\\\n/g'

}

### End functions


### Begin main

# Menu functions call script functions in the order listed.
# Pause to allow operator to read output.
function pause()
{
	read -p $'\n\e[0;31mPress ENTER key to continue.\e[0m' fackEnterKey

}

# Name, bind, configure, and provision user account(s)
function one()
{
	sitelocation
	bind
	configure
	users
	summary
	pause

}

# Provision user account(s)
function two()
{
	users
	summary
	pause

}

# Rename and rebind
function three()
{
	sitelocation
	bind
	configure
	summary
	pause

}

# Summary of current configuration
function four()
{
	summary
	pause

}

# Define menu display.
function menu()
{
	clear
	echo "EXAMPLE CO macOS ONBOARDING MENU"
	echo "Select an option below:"
	echo "-----------------------"
	echo "1. Name, join, configure, and provision user account(s)"
	echo "2. Provision user account(s)"
	echo "3. Rename and rejoin"
	echo "4. Summary of current configuration"
	echo "5. Exit"

}

# Read operator input and invoke functions.
function evalinput()
{
	local selection
	read -p $'\n\e[0;31mSelect an option [\e[0;33m1\e[0;31m - \e[0;33m5\e[0;31m]\e[0m ' selection
	case $selection in
		1) one ;;
		2) two ;;
		3) three ;;
		4) four ;;
		5) exit 0;;
		*) printf '\n\e[0;31mInvalid menu option.\e[0m' && sleep 2

	esac

}

# Menu loop.
while true
do
	menu
	evalinput

done

### End main

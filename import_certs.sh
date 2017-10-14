#!/bin/sh

# import_certs.sh
# Author: Kyle Brewer
# https://github.com/kylebrewer/macos-management
#
# Purpose: Add certificates to the System keychain, and remove misplaced
# certificates from users' Login keychains.

# Certificate storage path, name search strings, SHA-1 hashes, and filenames
# Local certificate storage path, which holds certs before deployment.
# For example: /Users/Shared/Certs
cert_path=""

# Common certificate name search string.
common_cert_name=""

# Certificate 1 filename and SHA-1 hash.
cert_1_filename=""
cert_1_hash=""

# Certificate 2 filename and SHA-1 hash.
cert_2_filename=""
cert_2_hash=""

# Certificate 3 filename and SHA-1 hash.
cert_3_filename=""
cert_3_hash=""

# Certificate 4 filename and SHA-1 hash.
cert_4_filename=""
cert_4_hash=""

# Root certificate name string, filename, and SHA-1 hash.
root_cert_name=""
root_cert_filename=""
root_cert_hash=""

# Confirm elevated permissions

# We need to execute as root to get some of this done.
# If the executing user is not root, the script will exit with code 1.
if [ "$USER" != "root" ]; then
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "You are attempting to execute this process as user $USER"
        echo "Please execute the script with elevated permissions."
        exit 1

fi

# Add trusted certs to the System keychain, as they will be shared by all users.
echo "Checking for existing certificates in System keychain."

# First, we'll search existing certificates in the System keychain.
# We'll create an arrary of certificates matching $common_cert_name and $root_cert_name from above.
# Note that the declared array consists of two commands, due to the lack of wildcard search support in "security find-certificate".
declare -a systemcerts=(`/usr/bin/security find-certificate -a -c "$common_cert_name" -Z /Library/Keychains/System.keychain | /usr/bin/grep ^SHA-1 | /usr/bin/sed 's/SHA-1 hash: //g'` \
`/usr/bin/security find-certificate -a -c "$root_cert_name" -Z /Library/Keychains/System.keychain | /usr/bin/grep ^SHA-1 | /usr/bin/sed 's/SHA-1 hash: //g'`)

# If a certificate does not exist, it will be added from the local certificate storage defined in $cert_path.
# Search array for certificate 1.
if `echo ${systemcerts[@]} | /usr/bin/grep -q "$cert_1_hash"`; then
        echo "Certificate 1 already exists in System keychain."
else
        /usr/bin/security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain $cert_path/$cert_1_filename
	echo "Certificate 1 added to System keychain."

fi

# Search array for certificate 2.
if `echo ${systemcerts[@]} | /usr/bin/grep -q "$cert_2_hash"`; then
        echo "Certificate 2 already exists in System keychain."
else
        /usr/bin/security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain $cert_path/$cert_2_filename
	echo "Certificate 2 added to System keychain."

fi

# Search array for certificate 3.
if `echo ${systemcerts[@]} | /usr/bin/grep -q "$cert_3_hash"`; then
        echo "Certificate 3 already exists in System keychain."
else
        /usr/bin/security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain $cert_path/$cert_3_filename
	echo "Certificate 3 added to System keychain."

fi

# Search array for certificate 4.
if `echo ${systemcerts[@]} | /usr/bin/grep -q "$cert_4_hash"`; then
        echo "Certificate 4 already exists in System keychain."
else
        /usr/bin/security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain $cert_path/$cert_4_filename
	echo "Certificate 4 added to System keychain."

fi

# Search array for root certificate.
if `echo ${systemcerts[@]} | /usr/bin/grep -q "$root_cert_hash"`; then
        echo "Root certificate already exists in System keychain."
else
        /usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $cert_path/$root_cert_filename
	echo "Root certificate added to System keychain."

fi

# Delete certs from user(s) login keychain(s).
echo "Removing certificates from user(s) login keychain(s)."

# Search for all local usernames, then loop through to remove the certificates from their individual keychains.
# find is spawned to collect user accounts, narrowing the search to only directories under /Users. sed does some cleaning.
# grep is called to exclude admin and Shared accounts, as well as any hidden directories that do not indicate user accounts.
for username in $(/usr/bin/find /Users -type d -mindepth 1 -maxdepth 1 | /usr/bin/sed 's#/Users/##g' | /usr/bin/grep -vE '(admin|Shared|.\*)')
do
	# We can't remove single certificates with names matching others, so we'll identify them by their known SHA-1 hashes.
	# First, we'll create array of existing certificates in the System keychain.
	# Note that the declared array consists of two commands, due to the lack of wildcard search support in "security find-certificate".
	declare -a logincerts=(`/usr/bin/security find-certificate -a -c "$common_cert_name" -Z /Users/$username/Library/Keychains/login.keychain | /usr/bin/grep ^SHA-1 | /usr/bin/sed 's/SHA-1 hash: //g'` \
`/usr/bin/security find-certificate -a -c "$root_cert_name" -Z /Users/$username/Library/Keychains/login.keychain | /usr/bin/grep ^SHA-1 | /usr/bin/sed 's/SHA-1 hash: //g'`)

        for hash in ${logincerts[@]}
        do
                /usr/bin/security delete-certificate -Z "$hash" /Users/$username/Library/Keychains/login.keychain
        done
done

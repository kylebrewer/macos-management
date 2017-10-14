#!/bin/sh

# dump_qe_db.sh
# Author: Kyle Brewer
# https://github.com/kylebrewer/macos-management
#
# Purpose: Report downloads recorded by OS X's QuarantineEvents.
#
# Usage:
# This script assumes the default intent is to target all local usernames, unless an argument is provided.
# Single-user mode: omgdownloads.sh <target_username>

# Check for argument and determine system-wide or single-user mode.
if [ -z "$1" ]; then
	# Target all local usernames, with exceptions defined below.
	echo "No target username specified. Running against all local usernames."
	# Search for all local usernames, then loop through the list.
	# find is spawned to collect user accounts, narrowing the search to only directories under /Users. sed does some cleaning.
	# grep is called to exclude /Users/admin and /Users/Shared paths, as well as any hidden directories that do not indicate accounts.
	for username in $(/usr/bin/find /Users -type d -mindepth 1 -maxdepth 1 | /usr/bin/sed 's#/Users/##g' | /usr/bin/grep -vE '(admin|Shared|.\*)')
	do
		database="/Users/$username/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"

		# Test for database. Run query if it exists, echo absence if not.
		if [ -f "$database" ]; then
			echo "*** Downloads by user $username (excluding PubSubAgent and CalendarAgent) from"
			echo "*** $database:"

			# This SQL query parses the QuarantineEvents database for time stamp (reformatted to UTC time from Cocoa epoch), application name, URL, and file.
			# The list is then sorted by time stamp, with most recent events first.
			# Finally, sed is called to make it readable.
			# Note PubSubAgent and CalendarAgent are ignored in the SQL query.  Edit to suit your needs.
			/usr/bin/sqlite3 -header -line $database \
			'select datetime(LSQuarantineTimeStamp, "unixepoch", "+31 year") AS LSQuarantineTimeStamp,LSQuarantineAgentName,LSQuarantineOriginURLString,LSQuarantineDataURLString from LSQuarantineEvent WHERE LSQuarantineAgentName NOT IN ("PubSubAgent", "CalendarAgent") order by LSQuarantineTimeStamp desc' |\
			sed 's/^[ \t]*LSQuarantineTimeStamp/UTC/g; s/^[ \t]*LSQuarantineAgentName/App /g; s/^[ \t]*LSQuarantineOriginURLString/URL /g; s/^[ \t]*LSQuarantineDataURLString/File/g'
			echo "*** End of report for user $username"
		else
			echo "User $username does not have a QuarantineEvents database"

		fi

	done

else
	# Target single username, defined by first argument from command line.
	username="$1"
	database="/Users/$username/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2"
	echo "Targeting only $username."
	# Test for database. Run query if it exists, echo absence if not.
	if [ -f "$database" ]; then
		echo "*** Downloads by user $username (excluding PubSubAgent and CalendarAgent) from"
		echo "*** $database:"

		# This SQL query parses the QuarantineEvents database for time stamp (reformatted to UTC time from Cocoa epoch), application name, URL, and file.
		# The list is then sorted by time stamp, with most recent events first.
		# Finally, sed is called to make it readable.
		# Note PubSubAgent and CalendarAgent are ignored in the SQL query.  Edit to suit your needs.
		/usr/bin/sqlite3 -header -line $database \
		'select datetime(LSQuarantineTimeStamp, "unixepoch", "+31 year") AS LSQuarantineTimeStamp,LSQuarantineAgentName,LSQuarantineOriginURLString,LSQuarantineDataURLString from LSQuarantineEvent WHERE LSQuarantineAgentName NOT IN ("PubSubAgent", "CalendarAgent") order by LSQuarantineTimeStamp desc' |\
		sed 's/^[ \t]*LSQuarantineTimeStamp/UTC/g; s/^[ \t]*LSQuarantineAgentName/App /g; s/^[ \t]*LSQuarantineOriginURLString/URL /g; s/^[ \t]*LSQuarantineDataURLString/File/g'
		echo "*** End of report for user $username"

	else
		echo "User $username does not have a QuarantineEvents database"

	fi

fi

exit 0

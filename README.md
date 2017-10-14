# macos-management
Scripts to help you quickly manage macOS clients across your enterprise.

### onboarding.sh
macOS onboarding script. Define hostname, join to Active Directory, define user accounts and local administrator group membership, and more.  Get your mac clients enterprise-ready in minutes.

Adjust the configuration options to suit your environment.


### import_certs.sh
Add certificates to the System keychain, and remove misplaced certificates from users' Login keychains.

Developed to maintain certificates across hundreds of macOS clients in a global enterprise.  It adds new certificates to the System keychain, applies the specified trust settings, and removes improperly placed certificates from all individual users' Login keychains.  My scenario involved managing a few certificates and one root certificate, so the script is configured as such.  It's easy enough to modify to suit your environment.

The script assumes that you keep your current certificates stored on each client, perhaps updating local copies via Apple Remote Desktop, Microsoft SCCM, or Jamf, when necessary.  For example, you may use /Users/Shared/Certs as your standard local certficate storage prior to deploying to the System keychain.  You will need to define this path, as well as individual certificate filenames.

If you intend to remove improperly placed certificates, you will also need to provide common name strings and known SHA-1 hashes for fingerprinting.  For example, in a case where multiple certificates share the name "cert 1", the SHA-1 hash will ensure that only the desired certificate is removed.


### dump_qe_db.sh
Shell script to report downloads recorded by QuarantineEvents.

Developed to search the QuarantineEvents database and report all downloads in a readable list.  This data may be useful for privacy or forensics purposes.

This script assumes the default intent is to target all local usernames, unless an argument is provided.  For example, to enable single-user mode:  omgdownloads.sh <target_username>

Note that PubSubAgent and CalendarAgent are ignored in the SQL query.  Edit the script to suit your needs.

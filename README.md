# datagather
Tool to collect useful information from systems.

Modularly designed, this complete rewrite creates XML and relies on no more
than POSIX and some minor additions that are fairly standard.

# Legacy tools

Some old stuff here is now explicitly legacy

## standalone

In the standalone directory:

parse_sudo: 
  - Reliably parse any valid(1) sudoers file
  - Will descend into included files
  - Can handle recursive aliases, tags, escaped spaces, etc.
  - A few possible output options, each one host, one user, one runas, one user:
    - Valid sudoers lines
    - key=value
    - XML (for datagather), manually created, no XML lib needed
  - Requires perl >= 5.10 (I use named capture groups for sanity)
    
logins:
  - Like logins(1M) of yore, but works
  - Relies on /usr/bin/getent, so sorry, won't work on macOS
  - Codes for password:
    - PS: A valid password exists
    - NL: No valid password, account is still accessible by other means
    - LK: Account is completely disabled (yes, on Linux, this means expired account)
    - NP: Password is empty (null)
  - Can output key=value, colon separated fields, JSON, or XML.
    - Not all fields printed in colon separated format.
  - Requires perl >= 5.10 (I use named capture groups for sanity)

(1): At least, I've yet to find anything that passes visudo that it doesn't correctly parse.

# Coding standards
Because this code needs to run on an insanely broad variety of systems, all
code is to be written using as close to POSIX as feasible.  Additional commands
should be checked for, not presumed, with workarounds for missing commands.

In addition, commands that are POSIX, but known to be less commonly available,
such as **bc** and **m4**, should be treated as risky.

# datagather
Tools to collect useful data from systems

parse_sudo: 
  - Reliably parse any valid(1) sudoers file
  - Will descend into included files
  - Can handle recursive aliases, tags, escaped spaces, etc.
  - A few possible output options, each one host, one user, one runas, one user:
    - Valid sudoers lines
    - key=value
  - This version is harder to read, but is designed to operate on very old perl
    - Makes no use of named capture groups
    
logins:
  - Like logins(1M) of yore, but works
  - Relies on /usr/bin/getent, so sorry, won't work on macOS
  - Codes for password:
    - PS: A valid password exists
    - NL: No valid password, account is still accessible by other means
    - LK: Account is completely disabled (yes, on Linux, this means expired account)
    - NP: Password is empty (null)
  - Can output key=value, colon separated fields, or JSON.
    - Not all fields printed in colon separated format.
  - This version is harder to read, but is designed to operate on very old perl
    - Makes no use of named capture groups

(1): At least, I've yet to find anything that passes visudo that it doesn't correctly parse.

# datagather
Tools to collect useful data from systems

parse_sudo: 
  - Reliably pass any valid sudoers file
  - Will parse into include files
  - A few possible output options, each one host, one user, one runas, one user:
    - Valid sudoers lines
    - key=value
    - JSON
    
logins:
  - Like logins(1M) of yore, but works
  - Relies on /usr/bin/getent, so sorry, won't work on macOS
  - Codes for password:
    - PS: A valid password exists
    - NL: No valid password, account is still accessible by other means
    - LK: Account is completely disabled (yes, on Linux, this means expired account)
    - NP: Password is empty (null)

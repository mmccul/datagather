<# 
  Fix the network

  Uses (currently hard coded) C:\Users\mmccul\bin\netconfig.xml)
  Needs to be in the format

  <config>
    <netdata> <!-- one or more of these -->
      <ssid />
      <v4>
        <ip />
        <defgw />
        <netmask />
      </v4>
      <dns>
        <dns4 />
        <dns6 />
        <searchpath /> <!-- one or more of these -->
      </dns>
    </netdata>
  </config>

  Add additional netdata stanzas.  Each ssid is exactly matched.  If found,
  sets the network parameters exactly as set, useful for static networks.

  If IPv4 is missing, rely on DHCP
  If DNS is missing (or only one provided, ignore/don't set.
    Makes little sense to set static IP without setting DNS, but you can.

  Haven't yet built the setting of v6 manually or other oddities there
#>

<# Escalate to admin rights if we don't have it already #>
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {   
    $arguments = "& '" + $myinvocation.mycommand.definition + "'"
      Start-Process powershell -Verb runAs -ArgumentList $arguments
    Break
}

<# 
  We only work (for now) on "Wi-Fi" interface.  Maybe later that will just
  be a default
#>

$curnet=get-netconnectionprofile -InterfaceAlias "Wi-Fi"
$index=$curnet.InterfaceIndex

$netdata=[XML](Get-Content C:\Users\mmccul\bin\netconfig.xml)

$found=0
$i=0
foreach ( $ssid in $netdata.config.netdata.ssid) {
    if ( $curnet.Name -eq $ssid ) {
        if ( $netdata.config.netdata[$i].v4.ip ) {
            $ip=$netdata.config.netdata[$i].v4
            $family="IPv4"
            $destpre="0.0.0.0/0"

            write-host "Static IP"
            $out=Remove-NetRoute `
              -InterfaceIndex $index `
              -DestinationPrefix $destpre `
              -Confirm:$false

            $out=remove-netipaddress `
              -InterfaceIndex $index `
              -AddressFamily $family `
              -Confirm:$false

            $out=set-netipinterface `
              -InterfaceIndex $index `
              -AddressFamily $family `
              -Dhcp Disabled

            $out=new-netipaddress `
              -InterfaceIndex $index `
              -AddressFamily $family `
              -IPAddress $ip.ip `
              -PrefixLength $ip.netmask `
              -DefaultGateway $ip.defgw
        } else {
            write-host "Dynamic IP"

            $out=set-dnsclientserveraddress `
              -InterfaceIndex $index `
              -ResetServerAddress

            $out=set-netipinterface `
              -InterfaceIndex $index `
              -AddressFamily $family `
              -Dhcp Enabled

            ipconfig /renew "Wi-Fi"
        }

        if ( $netdata.config.netdata[$i].v6.ip ) {
            $ip=$netdata.config.netdata[$i].v6
            $family="IPv6"
            $destpre="::/0"
            
            write-host "Static IPv6"
            $out=Remove-NetRoute `
              -InterfaceIndex $index `
              -DestinationPrefix $destpre `
              -Confirm:$false

            $out=remove-netipaddress `
              -InterfaceIndex $index `
              -AddressFamily $family `
              -Confirm:$false

            $out=set-netipinterface `
              -InterfaceIndex $index `
              -AddressFamily $family `
              -Dhcp Disabled

            $out=new-netipaddress `
              -InterfaceIndex $index `
              -AddressFamily $family `
              -IPAddress $ip.ip `
              -PrefixLength $ip.netmask `
              -DefaultGateway $ip.defgw
        } else {
            $out=set-netipinterface `
              -InterfaceIndex $index `
              -AddressFamily $family `
              -Dhcp Enabled
        }

        if ( $netdata.config.netdata[$i].dns ) {
            if ( $netdata.config.netdata[$i].dns.searchpath ) {
                write-host "Set DNS searchpath"
                set-dnsclientglobalsetting `
                  -SuffixSearchList $netdata.config.netdata[$i].dns.searchpath
            }
            if ( $netdata.config.netdata[$i].dns.dns4 -OR
                 $netdata.config.netdata[$i].dns.dns6 ) {
                write-host "Static DNS"
                $out=set-dnsclientserveraddress `
                  -InterfaceIndex $index `
                  -ServerAddresses $dns
            }
        }
        if ( -Not $netdata.config.netdata[$i].dns -And
             -Not $netdata.config.netdata[$i].v4 -And
             -Not $netdata.config.netdata[$i].v6 ) {
            
            $out=set-dnsclientserveraddress `
             -InterfaceIndex $index `
             -ResetServerAddress
 
            $out=set-netipinterface `
             -InterfaceIndex $index `
             -Dhcp Enabled

             ipconfig /renew "Wi-Fi"
        }
        $found=1
        break
    }
    $i=$i + 1
}


if ( $found -eq 0 ) {
    $out=set-dnsclientserveraddress `
     -InterfaceIndex $index `
     -ResetServerAddress
 
    $out=set-netipinterface `
     -InterfaceIndex $index `
     -Dhcp Enabled

     ipconfig /renew "Wi-Fi"
} 
 

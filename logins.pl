#!/usr/bin/perl
######################################################################
# logins.pl
#
# A better logins(1M) than the one that doesn't come with Linux
# Even outdoes FreeBSD's logins(8)
#
# Output:
#   Each user is printed in a specified format,
#   with the passwd field replaced with a two letter code:
#     PS : User has a valid password
#     LK : User is completely disabled
#     NL : User is enabled, but does not have a valid password
#     NP : User has a null password
#
#   Three output formats specified based on command line flag:
#     -t : colon separated values, no field names, 
#          order is passwd data, shadow data, group data
#     -k : key=value format
#     -j : JSON.  May want the -p for pretty JSON
#
# Input:
#   Uses getent because perl's getpwent isn't as smart as getent.
#   For FreeBSD, calls pw to get expiration and similar data
#
# Assumptions:
#   * getent works
#   * If using LDAP (e.g. AD) for accounts, account enumeration is enabled
#   * getent shadow returns actual hashes (means OSX doesn't work)
#   * That you are running with admin privileges
#
# Requirements:
#   * /bin/getent
#     - change to the right path if required, some OS based coding done
#   * /usr/sbin/pw
#     - Only for BSD OSs, because getent on BSD doesn't return key data
#   * perl-JSON
#     - if JSON output requested
######################################################################
use strict;
use Getopt::Std;
use POSIX qw(strftime);
use Socket;
use Sys::Hostname;

####
# Major vars
####
my @userlist;
our %opts;
our %grouplist;
our $getent="/usr/bin/getent";
our $pw="/usr/sbin/pw";
our $os;
our $host;
our @keyfiles;

####
# subroutines
####

####
# parsepass : Parse a given passwd and expire entry to determine the status code
####
sub parsepass {
    my $passwd=$_[0];
    my $expire=$_[1];
    my $type;
    my $passlen;
    my $salt;
    my $pass;
    my $today=int (time/86400);

    # Doublecheck this, may be platform specific
    if ( $expire < $today && $expire >= 0 ) {
        return "LK";
    }

    # BSD has a magic token for locked
    if ( $os =~ /bsd/i && $passwd =~ /^\*LOCKED\*/ ) {
        return "LK";
    }

    if ( $passwd eq "" ) {
        return "NP";
    }

    # Yes, bcrypt uses the "salt" for another parameter, ignore that, does
    # not affect what we are doing
    if ( $passwd =~ /^\$(\d\w?)\$([^\$]+)\$(.+)/ ) {
        $type=$1;
        $salt=$2;
        $pass=$3;
    } 
    else {
        $type="des";
        $salt=substr $passwd,0,2;
        $pass=substr $passwd,2;
    }
    $passlen=length($pass);

    if ( $pass !~ /[a-zA-Z0-9.\/]+/ ) { return "NL"; }
    if ( $salt !~ /[a-zA-Z0-9.\/]+/ ) { return "NL"; }

    if ( $type eq "1" ) { $type="md5"; }
    if ( $type =~ /2[a-zA-Z]/ ) { $type="bcrypt"; }
    if ( $type eq "5" ) { $type="sha256"; }
    if ( $type eq "6" ) { $type="sha512"; }
 
    if ( $type eq "md5" && $passlen != 22 ) { return "NL"; }
    if ( $type eq "bcrypt" && $passlen != 53 ) { return "NL"; }
    if ( $type eq "sha256" && $passlen != 43 ) { return "NL"; }
    if ( $type eq "sha512" && $passlen != 86 ) { return "NL"; }

    return "PS";
}

####
# initgroups : Initializes a map of group membership
# Why store some of these fields?  Because I may want them later and it hurts
# very little
####
sub initgroups {
    my %grouplist;

    while ( my @groupent=getgrent ) {
        my ($grname,$gpass,$gid,$members)=@groupent;
        $grouplist{name}{$grname}=$grname;
        $grouplist{$grname}{passwd}=$gpass;
        $grouplist{$grname}{gid}=$gid;
        $grouplist{reverse}{$gid}=$grname;
        $grouplist{$grname}{members}=$members;
    }
    return \%grouplist;
}

####
# getgroups: Returns a list of all groups a given individual is a member of
####
sub getgroups {
    my $name=$_[0];
    my $pgid=$_[1];
    my @groups;
    my %seen = ();

    push @groups, $grouplist{reverse}{$pgid};
    for my $group (keys %{ $grouplist{name} } ) {
        my $grmembers=$grouplist{$group}{members};
        foreach my $memb (split (' ',$grmembers)) {
            if ( $memb eq $name ) {
                push @groups, $group;
            }
        }
    }

    # Make the list unique, no double listing
    foreach my $item (@groups) {
        $seen{$item}++;
    }
    
    return keys %seen;

}

####
# If you don't know the usage routine by now...
####
sub usage {
    print "Display user logins information\n";
    print "$0 [-h]\n";
    print "$0 [-jknpst] [-g groupname] [-l username] [-a conf]\n";
    printf ("%-8s : Output traditional colon separated format\n","-t");
    printf ("%-8s : Output JSON\n","-j");
    printf ("%-8s : Use pretty format for JSON output\n","-p");
    printf ("%-8s : Output key=value pairs\n","-k");
    printf ("%-8s : Only print the named user\n","-l user");
    printf ("%-8s : Only print users who are members of the named group\n","-g group");
    printf ("%-8s : Add name of host invoking such in key value or JSON\n","-n");
    printf ("%-8s : Add SSH authorized keys in key value or JSON\n","-s");
    printf ("%-8s : Use conf instead of /etc/ssh/sshd_config\n","-a conf");
}

####
# Find authorized_keys files to search
# Intended to be called once, but multi-run safe
# Use -a conf to change where config lives away from /etc/ssh/sshd_config
####
sub get_keyfiles {
    if ( @keyfiles ) {
        return @keyfiles;
    }
    my $FH;
    @keyfiles=(".ssh/authorized_keys",".ssh/authorized_keys2");
    open ($FH,$opts{a});

    while ( my $line = <$FH> ) {
        $line =~ s/^\s*//;
        $line =~ s/#.*//;
        if ( $line eq "" ) {
            next;
        }
        if ( $line =~ /^Match\s/ ) { return @keyfiles; }
        if ( $line =~ /^AuthorizedKeysFile\s+(.+)/ ) {
            push (@keyfiles,split(/\s+/,$1));
            last;
        }
    }
}

####
# grabkeys
# Grabs all authorized keys and returns them as a list
####
sub grabkeys {
    my $homedir=shift;
    my @keys;

    if ( ! @keyfiles ) {
        # @keyfiles=get_keyfiles();
        get_keyfiles();
    }
    foreach my $keyfile (@keyfiles) {
        if ( -f "$homedir/$keyfile" ) {
            my $FH;
            open ($FH,"$homedir/$keyfile") || die "$homedir/$keyfile exists but cannot read\n";
            while (my $line = <$FH>) {
                chomp ($line);
                if ( $line =~ /^#/ ) { next; }
                push @keys,$line;
            }
        }
    }
    return @keys;
}

####
# Main code
####

# Parse options
getopts('ha:jtkpl:g:ns', \%opts);

if ( $opts{h} ) {
    &usage;
    exit 0;
}

$os=`env uname`;
chomp ($os);
if ( $os =~ /bsd/i ) {
    $getent = "/usr/bin/getent";
}

if ( $opts{n} ) {
    $opts{n}=hostname();
}

if ( ! $opts{a} ) {
    $opts{a}="/etc/ssh/sshd_config";
}

if ( ! $opts{j} && ! $opts{k} ) {
    $opts{t}=1;
}

if ( $opts{g} && $opts{l} ) {
    die "Sorry, -g and -l flags are mutually exclusive\n";
}

# Initialize Group list
my $groupref = &initgroups;
%grouplist= %{$groupref};

# Grab each user

my $FH;
open ($FH, "$getent passwd|") or die "Cannot getent passwd: $!"; 
while ( my $user = <$FH> ) {
    my @user;

    chomp $user;
    my ($name,$passwd,$uid,$gid,$gecos,$dir,$shell) = split(':',$user);
    if ( $opts{l} && $name ne $opts{l} ) { 
        next; 
    }

    # Get group membership
    my @groups=getgroups($name,$gid);
    if ( $opts{g} ) {
        my %grouphash;
        %grouphash = map { $_ => 1 } @groups;
        if ( ! exists ( $grouphash{$opts{g}} ) ) {
            next;
        }
    }

    # Get shadow info
    my $SH;
    my ($spnam,$sppasswd,$lastchg,$minage,$maxage,$warnage,$inactive,$expire,$reserved,$spclass,$spuid,$spgid,$spgecos,$spdir,$spshell);
    if ( $os !~ /bsd/i ) {
        open ($SH, "$getent shadow $name|");
        my $shadow=<$SH>;
        chomp $shadow;
        close ($SH);

        ($spnam,$sppasswd,$lastchg,$minage,$maxage,$warnage,$inactive,$expire,$reserved) = split(/:/,$shadow);
    } else {
        # BSD getent doesn't return expire or things like that, must use pw show
        open ($SH, "$pw user show $name|");
        my $shadow=<$SH>;
        chomp $shadow;
        ($spnam,$sppasswd,$spuid,$spgid,$spclass,$maxage,$expire,$spgecos,$spdir,$spshell) = split(/:/,$shadow);
        close ($SH);
        if ( $maxage > 0 ) {
            $maxage=int ($maxage/86400) - int (time/86400);
        }
        # A kludge because BSD uses 0 for no expiration, Linux, 0 has expiration
        if ( $expire == 0 ) { $expire=-1; }
    } 
    if ( $spnam ) {
        $passwd=$sppasswd;
    }
    if ( $expire eq "" ) { $expire=-1; }
    if ( $lastchg eq "" ) { $lastchg=-1; }
    if ( $minage eq "" ) { $minage=-1; }
    if ( $maxage eq "" ) { $maxage=-1; }
    $passwd = &parsepass($passwd,$expire);    
    @user=($name,$passwd,$uid,$gid,$gecos,$dir,$shell,$lastchg,$minage,$maxage,$warnage,$inactive,$expire,$reserved);

    
    # Yes, I should move this print to down below, but left here for simplicity
    # and debugging for weird cases where you want to know on which user
    # it is hanging, such as when local users print fine, but LDAP hangs.
    if ( $opts{t} ) {
        print join (':',@user),":",join (',',@groups),"\n";
    }
    if ( $opts{j} or $opts{k} ) {
        my %user;
        
        if ( $opts{n} ) {
            $user{srchost}=$opts{n};
        }
        $user{user}=$name;
        $user{passwd}=$passwd;
        $user{uid}=$uid;
        $user{gid}=$gid;
        $user{gecos}=$gecos;
        $user{dir}=$dir;
        $user{shell}=$shell;
        $user{minage}=$minage;
        $user{maxage}=$maxage;
        $user{last_passwd_change}=$lastchg;
        $user{warnage}=$warnage;
        $user{inactive}=$inactive;
        $user{expire}=$expire;
        if ( $opts{p} ) {
            if ( $expire>0 ) {
                $user{expire_human}=strftime("%Y-%m-%d", localtime($expire*86400));
            }
        }
        if ( $opts{s} ) {
           @{$user{ssh_keys}} = grabkeys($user{dir}); 
        }
        $user{groups}=\@groups;
        push @userlist, \%user;
    }
}

close ($FH);

# print results

if ( $opts{k} ) {
    my $userent;

    for $userent (@userlist) {
        for my $key (keys (%{$userent})) {
            if ( ref ${$userent}{$key} eq "ARRAY" ) {
                my $arraystr= join (',',@{${$userent}{$key}});
                printf("%s=\"%s\" ",$key,$arraystr);
            } else {
                printf("%s=\"%s\" ",$key,${$userent}{$key});
            }
        }
        print "\n";
    }
}

# Yes, normally you should include via use, but we want optional includes
# That also dictates how we implement the functions here so it doesn't
# croak at compile time.
if ( $opts{j} ) {
    require 'JSON.pm';
    my $enabled=1;
    my $json;
    $json = JSON->new->allow_nonref;
    # my $json = encode_json \@userlist;
    if ( $opts{p} ) {
        $json = $json->pretty->encode( \@userlist );
    } else {
        # $json = encode_json \@userlist;
        $json = JSON->new->utf8->encode(\@userlist);
    }
    print $json,"\n";
}

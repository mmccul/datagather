#!/usr/bin/perl
#############################################################################
# Parse sudoers data
#
# sudoers EBNF is an annoying format, especially because of aliases.  
# So let's read in the sudoers file, parse it, and simplify it to a format
# suitable for loading into a DB or similar central tool.
#
# Inputs:
# * By default, reads /etc/sudoers, unless overridden by command line flag
# * Reads any #include or #includedir associated files as sudo would
#
# Outputs:
# * Will report a cleaned up sudoers, either in valid sudoers format
#   * One line per user, host, runas, command
# * or in key=value format, again one line per user, host, runas, command
#
# Assumptions:
# * Needs standard perl modules, Getopt::Std and strict only
# * Only valid sudoers files are sent in.
# * While this is required for valid sudoers, included files/dirs should have
#   fully qualified paths.
#
# Issues:
# * No really clean way to avoid a global %opts state var since I use it
#   to report debug state, as well as how to report entries
# * aliases entry is currently listed as global, but could possibly be more
#   limited in scope
# * Haven't added the conditional JSON code, would require some refactoring
#
# License:
# Written and owned by Mark McCullough.  
#############################################################################
use Getopt::Std;
use strict;
use Socket;
use Sys::Hostname;

our %opts;
our %alias;
our $hostname;

####
# Let's get some arguments and return our global opts hash
####
sub parse_args {
    my %opts;
    getopts('hqdf:knp:jx',\%opts);
    if ( $opts{h} ) { usage(); }
    if ( $opts{n} ) { 
        $opts{n}=hostname(); 
    } 
    return %opts;
}

####
# Who doesn't write their own custom failure subroutine?
####
sub fail {
    my $message=shift;
    my $errorlevel=shift;

    if ( ! $errorlevel ) { $errorlevel=1; }
    if ( ! $opts{q} ) {
        print ("FAIL-$errorlevel:$message\n");
    }
    exit $errorlevel;
}

####
# I like my own usage statement as a subroutine
####
sub usage {
    print "$0 [-hdln] [-f filename]\n";
    printf ("%-13s: %s\n","-h","This help");
    printf ("%-13s: %s\n","-d","Debug mode");
    printf ("%-13s: %s\n","-k","Output in key=value format");
    printf ("%-13s: %s\n","-j","Output in JSON format, uses JSON pm");
    printf ("%-13s: %s\n","-f filename","Work on the specified filename");
    printf ("%-13s: %s\n","-q","Fatal errors should be silent");
    printf ("%-13s: %s\n","-n","In key/value form, print the hostname the entry came from");
    exit 0;
}

####
# Ah, useful stuff!  Here, we read directories and include the right files,
# calling read_file on each file.  This gets called from read_file itself
####
sub read_dir {
    my $dirname=shift;
    my $dh;
    my @data;

    opendir ($dh,$dirname) or fail ("Cannot open directory $dirname:$!");
    my @files = grep { !/[\.~]/ } readdir($dh);
    foreach my $file (@files) {
        debug ("read_dir: Do read $file");
        push (@data,read_file("$dirname/$file"));
    }
    return @data;
}

sub linecont {
    my $line=shift;
    my $fh=shift;

    while ( $line =~ /\\$/ ) {
        chomp $line;
        chop $line;
        $line = $line . <$fh>;
    }
    $line =~s/\s+/ /g;
    return $line;
}
        

####
# Read in an actual file.  The key thing this does is locate inclusions and
# recurse on those so that included directives occur in the right spot
####
sub read_file {
    my $file=shift;
    my $fh;
    my @data;
    my $hostname;

    # %h gets replaced by hostname up to first dot, another tweak to sudoers
    # include syntax, not the cleanest, but working on it
    if ( $file =~ /%h/ ) {
        if ( $opts{p} ) {
            $hostname=$opts{p};
        } else {
            $hostname=hostname();
        }
        $hostname=~s/\..+//;
        $file =~ s/%h/$hostname/;
    }
    open ($fh,$file) or fail ("Cannot open $file: $!");
    debug ("read_file: Parse $file");
    while ( my $line=<$fh> ) {
        $line =~ s/^\s+//;
        chomp $line;
        if ( $line =~ /^#include (?<includefile>.+)/ ) {
            push (@data,read_file($+{includefile}));
        }          
        if ( $line =~ /^#includedir (?<includedir>.+)/ ) { 
            push (@data,read_dir($+{includedir}));
        }

        # Handle line continuation characters
        $line=linecont($line,$fh);
        debug ("linecont returned $line"); 

        # So it turns out, you can have numeric userIDs as '#\d+' format
        # But those are tricky.  So delete comments based on not that pattern
        # You aren't allowed that pattern as a comment start per visudo,
        # so it is safe to use that as our trimmer.
        $line =~ s/#[^\d]+.*//;
        if ( $line =~ /^Defaults/ ) { next; }
        if ( $line ne "" ) { 
            debug ("Push |$line|");
            push (@data,$line);
        }
    }
    return @data;
}

####
# Just like custom fail routines, we all write our custom debug routines
####
sub debug {
    my $message = shift;
    if ( ! $opts{d} ) {
        return;
    }
    print "DEBUG: $message\n";
}

####
# Converts the datastructure of a given entry back into a valid sudoers line
####
sub mkline {
    my $entryptr=shift;
    my %entry=%$entryptr;
    my $line;

    if ( $entry{Runas} eq "" ) { 
        $line = "$entry{User} $entry{Host}=$entry{tag}$entry{Cmnd}";
    } else {
        $line = "$entry{User} $entry{Host}=($entry{Runas}) $entry{tag}$entry{Cmnd}";
    }
    return $line;
} 

####
# Hash value comparison is non-trivial in perl, but I know my tags, so I can
# do it without too much effort
####
sub comphash {
    my $ptr1=shift;
    my $ptr2=shift;
    my %hash1=%$ptr1;
    my %hash2=%$ptr2;

    if ( ( $hash1{User} ne $hash2{User} ) ||
       ( $hash1{Host} ne $hash2{Host} ) ||
       ( $hash1{Runas} ne $hash2{Runas} ) ||
       ( $hash1{tag} ne $hash2{tag} ) ||
       ( $hash1{Cmnd} ne $hash2{Cmnd} ) ) {
        return 0;
    }
    return 1;    
}

####
# Spit out a line, formatted according to the options presented
# Technically has side effects (print)
# Calls mkline
####
sub report {
    my $entryptr=shift;
    my %entry=%$entryptr;
    my $line;
    my $esccmd;
    my $runas;
    
    # Somehow, blank entries slip through, kludge around it
    unless ( $entry{Cmnd} && $entry{User} && $entry{Host} ) {
        return;
    }

    # Option specific output
    if ( $opts{k} ) { 
        $esccmd=$entry{Cmnd};
        $esccmd =~ s/"/\\"/g;
        if ( ! $entry{Runas} ) { 
            $runas="ALL"; 
        } else {
            $runas=$entry{Runas};
        }
        $line="user=\"$entry{User}\" host=\"$entry{Host}\" runas=\"$runas\" tag=\"$entry{tag}\" cmnd=\"$esccmd\"";
        if ( $opts{n} && ! $opts{p} ) {
            $line=$line . " srchost=\"$opts{n}\"";
        } elsif ( $opts{n} && $opts{p} ) {
            $line=$line . " srchost=\"$opts{p}\"";
        }

    } elsif ( $opts{x} ) {
        printf ("<sudoers_entry>\n");
        $esccmd=$entry{Cmnd};
        $esccmd =~ s/"/\\"/g;
        if ( ! $entry{Runas} ) { 
            $runas="ALL"; 
        } else {
            $runas=$entry{Runas};
        }
        for my $key (keys %entry) {
            printf ("  <%s>%s</%s>\n",$key,$entry{$key},$key);
        }
        printf ("</sudoers_entry>\n");
    } else {
        $line=mkline(\%entry);
    }
    print "$line\n";
}

####
# Main
####
my @sudo_lines;
my @cmds;
my @parts=("User","Host","Runas","Cmnd");
my @sudoerfiles;

%opts=parse_args();
if ( $opts{j} ) {
    require 'JSON.pm';
}

if ( $opts{f} ) {
    push (@sudoerfiles,$opts{f});
} else {
    push (@sudoerfiles,"/etc/sudoers");
}

# Recursively read sudoer data
while (my $file = shift @sudoerfiles) {
    push (@sudo_lines,read_file ($file));
}

# Now we have an array of lines, parse them, creating data structures for
# each line for easier analysis later, the main trick here is handling
# aliases, building a hash of aliases
while (my $line = shift @sudo_lines) {
    my %entry;

    # This giant regex is the match for an alias of any kind
    # Per the sudoers man page an alias name must be an upper case letter,
    # followed by an optional upper alphanum or underscore.  Confirmed by
    # visudo -c
    if ( $line =~ /(?<alias_type>(User|Host|Runas|Cmnd))_Alias\s+(?<alias_name>[A-Z][A-Z0-9_]*)\s*=\s*(?<alias_contents>.+)/ ) {
        $alias{$+{alias_type}}->{$+{alias_name}}=$+{alias_contents};
        next;
    }

    # This giant match is the master regex for a valid sudoers line.  Yes,
    # it is a mess.  
    $line =~ /^(?<user>.+)\s+(?<host>[^=]+)\s*=\s*(?:\(\s*(?<runas>[^\)]+)\s*\))?\s*(?<tag>(?:NOEXEC:|EXEC:|FOLLOW:|NOFOLLOW:|MAIL:|NOMAIL:|PASSWD:|NOPASSWD:|SETENV:|NOSETENV:|LOG_INPUT:|NOLOG_INPUT:|LOG_OUTPUT:|NOLOG_OUTPUT:)+)?\s*(?<cmd>.+)/;
    $entry{User}=$+{user};
    $entry{Host}=$+{host};
    $entry{Runas}=$+{runas};
    $entry{Cmnd}=$+{cmd};
    $entry{tag}=$+{tag};
    
    # Because of the nature of the Runas, we need another space trimmer to
    # ensure no trailing spaces
    $entry{Cmnd}=~ s/\s+$//;
    push (@cmds,\%entry);
}

# Now we do the real trickery, recursively expanding every alias for each
# section.  The report portion is in the section, because if an entry
# falls all the way through with no expansion, it is ready to report on
LINE: while (my $entryptr = shift @cmds) {
    # my %entry;
    my %entry=%$entryptr;
    my $line;
    my $updated=0;
    my $debugstr=mkline(\%entry);
    debug ("_main: Parsing |$debugstr|");

    foreach my $part (@parts) {
        # Extraneous line breaks creep in everywhere
        $entry{$part} =~ s/\s+$//;
        debug ("$part analysis on |$entry{$part}|");
        foreach my $element (split (/(?<!\\),\s*/,$entry{$part})) {
            my %newentry=%entry;
            if ( $alias{$part}{$element} ) {
                debug ("Expanding $element to $alias{$part}{$element}");
                $newentry{$part}=$alias{$part}{$element};
                unshift (@cmds,\%newentry);
                $updated=1;
                next;
            }
            $newentry{$part}=$element;
            if ( $part eq "Cmnd" ) {
                $newentry{Cmnd} =~ /(?<tag>(NOEXEC:|EXEC:|FOLLOW:|NOFOLLOW:|MAIL:|NOMAIL:|PASSWD:|NOPASSWD:|SETENV:|NOSETENV:|LOG_INPUT:|NOLOG_INPUT:|LOG_OUTPUT:|NOLOG_OUTPUT:)+)?\s*(?<rest>.+)/;
                if ( $+{tag} ne "" ) {
                    $entry{tag}=$+{tag};
                    debug ("tag: Set tag to |$+{tag}|");
                    $newentry{tag}=$+{tag};
                    $newentry{Cmnd}=$+{rest};
                }
            }
            if ( comphash (\%entry,\%newentry) == 0 ) {
                my $newline=mkline(\%newentry);
                debug ("unshift $newline");
                unshift (@cmds,\%newentry);
                $updated=1;
                next;
            }
        }
        if ( $updated == 1 ) {
            next LINE;
        }
    }
    report (\%entry);
}

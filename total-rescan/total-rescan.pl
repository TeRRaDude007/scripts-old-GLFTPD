#!/usr/bin/perl -w
############## ############## ############## ############## ############## ######## #### ## #
# total-rescan (c) daxxar ^ team pzs-ng <daxxar@daxxar.com> 
#  - version 1.3 rc3
#

#.########################################################################,
 # THIS SCRIPT *MUST* RUN AS ROOT, DUE TO chroot! IT CANNOT RUN WITHOUT!  #
 # (will give an error like "- Chroot failed! (Operation not permitted)") #
#`#######################################################################�

#
# info:
#  this is a pure perlscript, and also not using any modules.
#  it rescans a dir and all subdirs that contain a .sfv (or .zip, see $zipscan)
#  this is probably only useful if you've had fsck delete some files or if 
#  you've moved files to the site without using ftp, or before
#  zipscript was installed. it runs a given rescan binary from chroot
#  inside any dirs that have a .sfv/zip-file. :-) (see $zipscan)
#  it will print one line for each 'rescan', and it'll be "+ PASSED:" or
#  "- FAILED:", based on the returnvalue of rescan binary. all output
#  from the rescan binary is supressed. :)
#
# config/setup:
#  requires NO config or setup, unless glroot/bin/rescan isn't your rescan binary.
#  if so, change '$rescan'-variable below. the only other things you need to take
#  care of is commandline. you run the script with:
#   ./total-rescan.pl PATH-I-WANT-TO-RESCAN GLFTPD-ROOT-DIRECTORY
#  GLFTPD-ROOT-DIRECTORY is optional, defaults to /glftpd (should be ok for most people).
#  PATH-I-WANT-TO-RESCAN is RELATIVE to GLFTPD-ROOT-DIRECTORY, so if you do this:
#  ./total-rescan.pl site/games
#  it will rescan /glftpd/site/games/, and not ./site/games/.
#  morale is: remember to include site/-prefix, if you need it. :-) (thanks _-] :)
#  
# history:
#  version 1 is a full rewrite of total-rescan 0.x,
#  so i thought giving it its own version number was
#  the least i could do ;) 
#  
# changelog:
#  from 1.3
#  + support for zip-rescanning too ;) (see $zipscan, default on)
#  + preserves mtime/atime of the dir being rescanned (thanks iNDi).
#    (see $preservestamp) this will (supposedly) make site new work ok. ;)
#  ! now you can set $stampfromfile to use first .sfv/.zip in the dir for the mtime/atime,
#    instead of the dir itself. :) (only if preservestmap)
#  * getscandirs wasn't closing the dirhandle if there were no zips/sfvs in a dir.
#  ! "path" is now "pattern"; glob-matched pattern. :)
#  ! lists my real email in here now. =P
#
#  from 1.2
#  * rmlog.sh was accidentally overwritten at end of script, fixed. 
#  ! didn't work with perl 5.005, switched to -w and two-argument open()
#
#  from 1.1
#  + rmlog.sh-generate feature. :-) (script to remove all failed dirs)
#  * rmlog.sh generated in / now. :)
#  * rmlog.sh now generates newlines, and fixed a broken conditional :)
#  * total-rescan actually (perhaps) works. (note to self: rescan always
#    returns null, no matter what)
#  ! rmlog.sh is cleaned out at start of run, and prints two lines. ;)
#
#  from 1.0
#   ! output messages
#   * not working due to no chdir to / after chroot
#   * not working due to a misnamed sub (recandirs, not rescandirs)
#   - check for absolute path
#
#  from 0.x
#   ! full rewrite
#
# key   description
#  +    added
#  -    removed
#  *    bugfix
#  !    change
# (please, report bugs and / or send feature requests to daxxar@daxxar.com)
############## ############## ############## ############## ############## ######## #### ## #

use strict;

my $rescan = 'bin/rescan';	# Change if you've moved it / using another rescanner.
my $rmscript = 'rmlog.sh';	# Generates 'rmlog.sh' in currentdir, containing rm -rf "$dir" on all failed rels.
							# Set to '' to disable this feature. ;-)
my $zipscan = 1;			# Set to 0 if you do not want to rescan dirs with .zips. :)
my $preservestamp = 1;		# Set to 0 if you do not want to preserve timestamps on dirs.
my $stampfromfile = 0;		# Set to 1 if you want to fetch the timestamp from the first zip/sfv-file in thedir.
							# Useful for people who've run the original script (1.4rc1 or before), and want to regen.

my $version = '.4 rc3';		# Do not change. ;-)

print "+ Starting total rescan v1$version by daxxar ^ team pzs-ng.\n";

my $path = shift;
my $glroot = shift || '/glftpd';
$glroot =~ s/(?<!\/)$/\//;

if (!defined($path)) {
	print STDERR "- Path to scan not defined, exiting.\n";
	print STDERR "  (syntax: $0 <pattern> [glroot], pattern is relative to glroot, and a standard shell-pattern)\n";
	exit 1;
}

sub getdirs {
	my @dlist = (shift);
	my @dirs = @dlist;
	while ((my $dir = shift @dirs)) {
		if (!opendir(DIR, $dir)) {
			print STDERR "- Opening directtory '$dir' for reading failed, skipping! ($!)\n";
			next;
		}
		while (($_ = readdir(DIR))) {
			if (/^\./ || ! -d "$dir/$_") { next; }
			unshift(@dirs, "$dir/$_"); 
			push(@dlist, "$dir/$_");
		}
		closedir(DIR);
	}
	return @dlist;
}

sub getscandirs {
	my @dlist = @_;
	my @scandlist;
	DIR: foreach my $dir (@dlist) {
		if (!opendir(DIR, $dir)) {
			print STDERR "- Opening directory '$dir' for reading failed, skipping! ($!)\n";
			next;
		}
		
		while (($_ = readdir(DIR))) {
			if (/^\./ || -d "$_") { next; }
			if (/\.sfv$/i) {
				push(@scandlist, $dir);
				closedir(DIR);
				next DIR;
			}
			if ($zipscan && /\.zip$/i) {
				push(@scandlist, $dir);
				closedir(DIR);
				next DIR;
			}
		}
		# In case the dir is without .sfv/.zip. :)
		closedir(DIR);
	}
	return @scandlist;
}

sub rescandirs {
	my @dirs = @_;
	foreach my $dir (@dirs) {
		if (!chdir($dir)) {
			print STDERR "- Changing dir to '$dir' failed, skipping! ($!)\n";
			next;
		}

		my ($atime, $mtime);
		if ($preservestamp) {
			($atime, $mtime) = (stat( (glob('*.{sfv,zip}'))[0] )[8, 9] if $stampfromfile;
			($atime, $mtime) = (stat('.'))[8, 9] if not $stampfromfile;
		}

		my $output = `/bin/rescan`;
		my ($passed, $total) = (-1, -1);
		if ($output =~ /Passed ?: ?(\d+)$/m) { $passed = $1; }
		if ($output =~ /Total ?: ?(\d+)$/m) { $total = $1; }
		
		if ($passed == -1 || $total == -1) {
			print "- ERROR! Output from /bin/rescan on '$dir' was unparseable. (Nonstandard rescan binary?)\n";
		} elsif ($passed == $total) {
			print "+ PASSED: $dir\n";
		} else {
			print STDERR "- FAILED: $dir\n";
			if (defined($rmscript) && $rmscript ne '') {
				open(RMLOG, ">>/$rmscript");
				print RMLOG "rm -rf '$glroot$dir'\n";
				close(RMLOG);
			}
		}
		
		utime($atime, $mtime, '.') if $preservestamp;
		
		chdir('/');
	}
}

print "+ Changing root for script to '$glroot' and changing dir to '/'.\n";
if (!chroot($glroot)) {
	print STDERR "- Changing root failed! ($!)\n";
	exit 1;
}
if (!chdir('/')) {
	print STDERR "- WTF? Changing dir to '/' failed! ($!)\n";
	exit 1;
}

while (my $current = glob $path) {
	if (! -d $path) {
		print STDERR "! Pattern '${glroot}${path}' matches a something that's not a dir (or does not exist)!\n";
		print STDERR "  (syntax: $0 <pattern> [glroot], pattern is relative to glroot, and a standard shell-pattern)\n";
		exit 1;
	}
}


print "+ Cleaning rmscript (/$rmscript)\n";
open(RMLOG, ">/$rmscript");
print RMLOG "echo '* Starting deletion of failed dirs.. :)'\n";
close(RMLOG);

print "+ Caching directories recursively based on pattern '$path'.\n";
my @dirs;
while (my $current = scalar glob $path) { @dirs = (@dirs, getdirs($current)); }

print "+ Scanning dirs for sfv-files.\n" if not $zipscan;
print "+ Scanning dirs for sfv/zip-files.\n" if $zipscan;
my @scandirs = getscandirs(@dirs);
if (!@scandirs) {
	print STDERR "! Could not find any dirs containing any SFVs under '$path', exiting.\n" if not $zipscan;
	print STDERR "! Could not find any dirs containing any SFVs or ZIPs under '$path', exiting.\n" if $zipscan;
	exit 1;
}

print "+ Rescanning all dirs.\n";
rescandirs(@scandirs);

print "+ Adding 'closing entry' to rmscript ;)\n";
open(RMLOG, ">>/$rmscript");
print RMLOG "echo '* All done with deletion! :D'\n";
close(RMLOG);

print "+ Done! :)\n";

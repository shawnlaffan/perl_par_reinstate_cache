#!/usr/bin/perl -w
# Forked from PAR::Packer's myldr/Makefile.PL which is Copyright 2002-2009 by Audrey Tang.
# Modifications are copyright (c) 2009 Steffen Mueller.
#
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

use strict;
use Config;
use File::Spec;
use ExtUtils::Embed;
use DynaLoader;
use File::Basename;

xsinit(undef);

# used for searching libperls.
sub find_file {
    my $file = shift;

    my @paths = (
	    $Config{bin},
    	File::Spec->catdir($Config{'archlibexp'}, 'CORE'),
	    split(/\Q$Config{path_sep}\E/, $ENV{$Config{ldlibpthname}} || ''),
    	split(/ /, $Config{libpth}),
    );

    my $libperl;
    if ($libperl = DynaLoader::dl_findfile("-lperl")) {
        if (-l $libperl) {
            my $realpath = readlink($libperl);
            if (!File::Spec->file_name_is_absolute($realpath)) {
                $realpath = File::Spec->rel2abs(
                    File::Spec->catfile(
                        dirname($libperl) => $realpath
                    )
                );
            }
            $libperl = $realpath;
        }
        return $libperl if -e $libperl;
    }

    foreach my $path (@paths) {
	    $libperl = File::Spec->catfile($path, $file);
    	return $libperl if -e $libperl;
        
    	# for MinGW
	    $libperl = File::Spec->catfile($path, $1) if $file =~ /^lib(.+)/;
    	return $libperl if -e $libperl;
        
       	# for Cygwin
    	$libperl = File::Spec->catfile($path, $file.$Config{_a});
    	return $libperl if -e $libperl;
    }
}

my $debug = $ENV{DEBUG};
my $chunk_size = 30000;
my $perl = $^X;
my $exe = $Config{_exe};
my $link_exe = (($^O eq 'os2' and $Config{ldflags} =~ /-Zexe/) ? '' : $exe);
my $o = $Config{obj_ext};
my $gccversion = $Config{gccversion};
my $pccflags = ccopts();
my $pldflags = ldopts();
my $dynperl = $Config{useshrplib} && ($Config{useshrplib} ne 'false');

$dynperl = 1 if $pldflags =~ /\B-lperl\b/; # Gentoo lies to us!

my $cc = $Config{cc};
my $ld = $Config{ld} || (($^O eq 'MSWin32') ? 'link.exe' : $Config{cc});
$ld = $Config{cc} if ($^O =~ /^(?:dec_osf|aix|hpux)$/);

my $myperl_exe = File::Spec->catfile('.', "perl$exe");
my $myperl_exe_link = File::Spec->catfile('.', "perl$link_exe");
my $myperl_static_exe = File::Spec->catfile('.', "staticperl$exe");
my $myperl_static_exe_link = File::Spec->catfile('.', "staticperl$link_exe");
my $perl_mod = File::Spec->catfile(qw/.. blib lib PAR Packer WithPerl Static.pm/);
my $perldyn_mod = File::Spec->catfile(qw/.. blib lib PAR Packer WithPerl Dynamic.pm/);
my $lib_path = join(' ', map qq(-I"$_"), @INC);

my( $out, $ccdebug, $lddebug, $warn, $rm, $mv, $res, $long_literal, $mt_cmd );

if( $cc =~ m/^cl\b/i ) {
    $out = '-out:';
    $ccdebug = $debug ? '-Zi -Zm1000 ' : '-Zm1000 ';
    $lddebug = $debug ? '-debug ' : '-release ';
    $warn = $debug ? '-W3' : '';
    $res = $Config{ivsize} == 4 ? 'win32.obj' : '';
    $long_literal = 0;
    # Embed the manifest file for VC 2005 (aka VC8) or higher, but not for the
    # 64-bit Platform SDK compiler
    if( $Config{ivsize} == 4 and $Config{ccversion} =~ /^(\d+)/ and $1 >= 14 ) {
        $mt_cmd = 'mt -nologo -manifest $@.manifest -outputresource:$@;1';
    } else {
        $mt_cmd = '-$(NOOP)';
    }
} elsif ($cc =~ m/^gcc\b/i or ($cc =~ m/^cc\b/i and $gccversion)) {
    $out = '-o ';
    $ccdebug = $debug ? '-g ' : '';
    $lddebug = ($debug or $^O eq 'darwin') ? '' : '-s ';
    $warn = $debug ? '-Wall -Wno-comments ' : '';
    $res = ($^O =~ /^(?:MSWin|cygwin)/) ? 'win32.coff' : '';
    $long_literal = 1;
    $mt_cmd = '-$(NOOP)';
} else {
    $out = '-o ';
    $ccdebug = '';
    $lddebug = '';
    $warn = '';
    $res = '';
    $long_literal = 0; # better safe than sorry
    $mt_cmd = '-$(NOOP)';
}


my $perl58lib = "";
if($ENV{ACTIVEPERL_MINGW} and $Config{cf_email}=~/ActiveState.com/i){
    chomp $pldflags;
    $perl58lib = "-l$Config{libperl}";
    $perl58lib =~ s/\.lib$//;
}
my $cflags = "$ccdebug$warn$pccflags";
my $ldflags = "$lddebug$pldflags $perl58lib";
my $static_ldflags = $ldflags;

$static_ldflags =~ s/\s+-lperl\s+/ /g;

my $libperl;

if ($dynperl and $^O eq 'os2') {
    $libperl = OS2::DLLname();
}
elsif ($dynperl) {
    my $file = $Config{libperl};
    my $so = $Config{so} || 'so';
    $file = "libperl.$so" if $file eq 'libper'; # workaround Red Hat bug

    $file =~ s/\.(?!\d)[^.]*$/.$Config{so}/;
    $file =~ s/^lib// if $^O eq "MSWin32";

    $libperl = find_file($file);
    if (not -e $libperl) {
        $file =~ s/\.(?!\d)[^.]*$/.a/;
        $libperl = find_file($file);
    }

    # die "Can't find $file in (@paths) -- please contact the author!"
    # 	unless -e $libperl;
    undef $dynperl if !-e $libperl;
}

if (not $dynperl) {
    my $file = $Config{libperl};
    $file = 'libperl.a' if $file eq 'libper'; # same redhat bug? Just making sure...
    $libperl = find_file($file);
    $ldflags = $static_ldflags;
}

my $par = (($dynperl && $^O ne 'os2') ? $myperl_static_exe : $myperl_exe);
my $all = (
    $dynperl
    ? "$myperl_exe store_dynperl_in_module"
    #? "$myperl_static_exe $myperl_exe store_perl_in_module store_dynperl_in_module"
    : "$myperl_exe store_perl_in_module"
);

$perl = Win32::GetShortPathName($perl)
    if $perl =~ / / and defined &Win32::GetShortPathName;


# Determine whether we can find a config.h. If yes, include it in
# usernamefrompwuid.h. If not, set I_PWD to undefined in that header.
# -- Steffen
my $configh = "$Config::Config{archlibexp}/CORE/config.h";
open PWOUT, '> usernamefrompwuid.h' or die "open 'usernamefrompwuid.h': $!";
if (not -f $configh) {
    print PWOUT "#undef I_PWD\n";
}
else {
    print PWOUT "#include \"$configh\"\n";
}
close PWOUT;


print "Writing Makefile for the par$exe program\n";

open OUT, "> Makefile" or die "open 'Makefile': $!";

$rm = $^O eq 'MSWin32' ? '$(PERL) -MExtUtils::Command -e rm_f' : 'rm -f';
$mv = $^O eq 'MSWin32' ? '$(PERL) -MExtUtils::Command -e mv' : 'mv';

# XXX - Commented out this chunk (rt.cpan #16075)
#       not sure what the condition was testing against - disabled for now.
# if (-e $myperl_exe and not -s $myperl_exe) {
#     print OUT "all ::\n\t$^X -e1\n";
# }
# else {
    print OUT << "EOT";
# AUTOGENERATED, DO NOT EDIT, RERUN Makefile.PL

RM=$rm
MV=$mv
PERL=$perl
LD=$ld
CC=$cc
CFLAGS=$cflags
LDFLAGS=$Config{ldflags}
PERL_LDFLAGS=$ldflags
STATIC_LDFLAGS=$static_ldflags
NOOP=\$(PERL) -e1

OBJECTS=main$o $res

.c$o:
	\$(CC) -c \$(CFLAGS) \$<

all: $all

main$o: main.c perlxsi.c mktmpdir.c internals.c mktmpdir.h utils.c sha1.c

main.c: perlxsi.c mktmpdir.c internals.c

mktmpdir.c: mktmpdir.h

mktmpdir.h: utils.c sha1.c

clean:
	-\$(RM) my_*.c
	-\$(RM) main$o static$o
	-\$(RM) static$o
	-\$(RM) sha1$o sha1.c
	-\$(RM) *.opt *.pdb perlxsi.c
	-\$(RM) usernamefrompwuid.h
	\$(MV) Makefile Makefile.old

realclean: clean
	-\$(RM) $myperl_exe
	-\$(RM) $myperl_static_exe
	-\$(RM) Makefile Makefile.old

distclean: clean
	-\$(RM) $myperl_exe
	-\$(RM) $myperl_static_exe
	-\$(RM) Makefile Makefile.old

$myperl_exe: sha1$o \$(OBJECTS)
	\$(LD) \$(OBJECTS) \$(PERL_LDFLAGS) $out$myperl_exe_link
	$mt_cmd

disttest:
	-\$(NOOP)

test:
	-\$(NOOP)

.DEFAULT:
	-\$(NOOP)

.SUFFIXES: $o

sha1.c: sha1.c.PL
	\$(PERL) sha1.c.PL sha1.c

EOT

    print OUT << "EOT" if $dynperl;

#static$o: mktmpdir.c

#$myperl_static_exe: sha1$o static$o
#	\$(LD) static$o \$(STATIC_LDFLAGS) $res $out$myperl_static_exe_link
#	$mt_cmd

store_perl_in_module: $par
#	\$(PERL) -e "chmod(oct('0600'), '$perl_mod');"
#	\$(PERL) encode_append.pl $par $perl_mod
#	\$(PERL) -e "chmod(oct('0444'), '$perl_mod');"
#
store_dynperl_in_module: $myperl_exe
	\$(PERL) -e "chmod(oct('0600'), '$perldyn_mod');"
	\$(PERL) encode_append.pl $myperl_exe $perldyn_mod
	\$(PERL) -e "chmod(oct('0444'), '$perldyn_mod');"

EOT
# }

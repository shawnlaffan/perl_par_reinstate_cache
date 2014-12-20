use strict;
use warnings;
use PAR::Filter;
use ExtUtils::MakeMaker;
use File::Spec;

my $output_file = "parClientBootstrap.pl";

# This looks icky because the files are
# INCLUDED VERBATIM IN THE ORDER THEY APPEAR HERE!
# That means we need to resolve and intra-distribution, inter-file
# dependencies manually. For recursive compile-time dependencies, we
# manually fuzz with the code. See the end of this program.
my $modules = [
  { name => 'MIME::Base64::Perl',         modules => [qw()] },
  { name => 'URI',                        modules => [
    qw(URI::Escape URI),
    (map {"URI::$_"} reverse qw(
        rsync Heuristic QueryParam Split URL WithBase _foreign
        data file file::FAT file::Mac file::OS2 file::QNX
        file::Unix file::Win32 file::Base 
        ftp gopher  mms https http 
        _ldap _login _segment _server _generic _query _userpass
    )),
  ] },

  { name => 'version',
    manual_include_files => [
      {file => 'include/version/vpp.pm', module_name => 'version::vpp', inc_file => 'version/vpp.pm'},
      {file => 'include/version.pm',     module_name => 'version',      inc_file => 'version.pm'},
    ],
    #conditional => '$] < 5.010',
  },

  { name => 'Params::Check',              modules => [qw()] },
  { name => 'Module::Load',               modules => [qw()] },
  { name => 'Module::Load::Conditional',  modules => [qw()] },
  { name => 'IPC::Run',                   modules => [qw(IPC::Run::Debug IPC::Run::Timer
                                                         IPC::Run IPC::Run::IO IPC::Run::Win32Helper
                                                         IPC::Run::Win32IO IPC::Run::Win32Pump)] },
  { name => 'IPC::Cmd',                   modules => [qw()] },
  { name => 'File::Fetch',                modules => [qw()] },

  { name => 'PAR::Dist',                  modules => [qw()] },
  { name => 'ExtUtils::InferConfig',      modules => [qw()] },
];

my $script_code = <<'HERE';
package main;
use 5.006;
use strict;
use warnings;
use File::Spec;
use Getopt::Long;

sub usage {
  warn <<USAGE;
Usage: $0 [--perl=/path/to/perl] [--mirror=URL-to-CPAN-mirror]
USAGE
  exit(1);
}

my $perl = $^X;
my $mirror = "http://cpan.org";
my $author = "SMUELLER";

GetOptions(
  'perl=s' => \$perl,
  'mirror=s' => \$mirror,
  'h|help|?' => \&usage,
  'author=s' => \$author,
);

$mirror =~ s/\/$//;

warn("Invalid perl '$perl'!\n"), usage() unless -x $perl;

HERE

my $script_end_code = <<'HERE';

package main;

$Module::Load::Conditional::CHECK_INC_HASH = 1; # fix for IPC::Cmd/IPC::Run

my $config = ExtUtils::InferConfig->new($perl)->get_config();
die "Could not determine configuration of the target perl interpreter '$perl'!" unless ref $config;

my $installation_targets = {
  auto_inst_lib_conversion => 1,
  inst_lib     => $config->{installsitelib},
  inst_archlib => $config->{installsitearch},
  inst_script  => $config->{installscript},
  inst_bin     => $config->{installbin},
  inst_man1dir => $config->{installman1dir},
  inst_man3dir => $config->{installman3dir},
#  packlist_read                   $Config{sitearchexp}/auto/$name/.packlist,
#  packlist_write                  $Config{installsitearch}/auto/$name/.packlist,
};

my @find_dists = qw(
  PAR-Repository-Client
);

my $author_url = "$mirror/authors/id/".substr($author, 0, 1)."/".substr($author, 0, 2)."/$author";
my $ff_checksums   = File::Fetch->new(uri => "$author_url/CHECKSUMS");
my $checksums_file = $ff_checksums->fetch( to => File::Spec->tmpdir );
my $checksums;
eval {
  $checksums = do {open my $fh, '<', $checksums_file or die $!; local $/; <$fh>};
};
unlink $checksums_file;
die $@ if $@;

my $cksum;
{eval $checksums}; # only safe-ish because we trust PAUSE anyway.
die "Error evaluating checksums: $@" if $@;

require Config;
my $this_perlver = $Config::Config{version};
my $this_arch    = $Config::Config{archname};

my @available_pars;
foreach my $filename (keys %$cksum) {
  next unless $filename =~ /\.par$/;
  my ($distname, $distver, $arch, $perlver) = PAR::Dist::parse_dist_name($filename);
  next unless defined $perlver and defined $distname;
  next unless $perlver eq 'any_version' or $perlver eq $this_perlver;
  next unless $arch eq 'any_arch' or $arch eq $this_arch;
  push @available_pars, {
    file => $filename,
    distname => $distname,
    perlver => $perlver,
    arch => $arch,
  };
}
use Data::Dumper;
warn Dumper \@available_pars;

#END {
#use Data::Dumper;
#warn Dumper \%INC;
#}

HERE

my %seen;
foreach my $mod (@$modules) {
  my @modules = @{$mod->{modules}||[]};
  push @modules, $mod->{name} if not exists $mod->{manual_include_files};
  @modules = map {find_module_file($_)} @modules;
  push @modules, @{$mod->{manual_include_files}}
    if exists $mod->{manual_include_files};

  foreach my $module (@modules) {
    my $module_name = $module->{module_name};
    next if $seen{$module_name}++;
    my $file = $module->{file};
    my $module_file = $module->{inc_file};
    warn $module_file;

    my $version = MM->parse_version($file);
    $version ||= '0';

    open my $fh, '<', $file or die $!;
    my $code;
    while (<$fh>) {
      last if /^__(?:END|DATA)__\s*$/;
      if ($module_name eq 'IPC::Run') {
        s/^\s*require\s+IPC::Run::IO\s*;/package IPC::Run::IO; package IPC::Run;/;
        s/\bmy IPC::Run::IO /my /;
      }
      elsif ($module_name eq 'IPC::Run::Timer') {
        s/^\s*require\s+IPC::Run\s*;/package IPC::Run; package IPC::Run::Timer;/;
      }
      elsif ($module_name eq 'include/version.pm') {
        s/(eval\s*"use\s*version::vpp\s*\$VERSION";\s*)/0 and /; # Oh yessss!
      }
      if (/Locale::Maketext::Simple/) {
        $_ = 'sub loc {my $ref = shift; $ref =~ s/\%\d/\%s/g; return sprintf($ref, @_);}'."\n";
      }
      s/MIME::Base64(?!::Perl)/MIME::Base64::Perl/g;
      $code .= $_;
    }
    close $fh;

    my $extra_conditional = exists($mod->{conditional}) ? " and ($mod->{conditional})" : "";
    my $res = PAR::Filter->new("PodStrip")->apply(\$code);
    $$res =
      join "\n",
      map { s{^#line(\s*\d+)(.*)$}{"#line$1" . (defined($2) ? " \"$module_name\"" : '')}gme; $_ }
      split /\n/, $$res;
    $$res = <<HERE1 . $$res . <<HERE2;
#######################################################
# Start of '$module_name' VERSION $version
#######################################################
BEGIN { no strict; no warnings;
    if ("$module_name" !~ /win32/i or \$^O =~ /win32/i or '$module_name' eq 'URI::file::Win32'$extra_conditional) {
    my \$res = eval <<'____EVALBLOCK_$module_name';
#######################################################
HERE1
#######################################################
____EVALBLOCK_$module_name
  warn "PROBLEM: \$@" if \$@;
  \$INC{"$module_file"} = "$output_file" if \$res;
} }
#######################################################
# End of '$module_file' VERSION $version
#######################################################
HERE2

    $script_code .= $$res. "\n";
  }
}

open my $fh, '>', $output_file or die $!;
print $fh $script_code;
print $fh $script_end_code;


sub find_in_inc {
  my $module_file = shift;
  
  foreach my $inc (@INC) {
    my $file = File::Spec->catdir($inc, $module_file);
    return $file if -e $file;
  }
  return();
}

sub find_module_file {
  my $module = shift;
  my $module_file = $module . ".pm";
  $module_file =~ s/::/\//g;

  my $file;
  if (!eval "require $module;" or !exists($INC{$module_file})) {
    $file = $INC{"$module_file"};
    warn "Couldn't require '$module'. Falling back to \@INC search.";
    $file = find_in_inc($module_file);
  }
  else {
    $file = $INC{$module_file};
  }
  die "Could not find module '$module'!" unless defined $file;
  return {module_name => $module, file => $file, inc_file => $module_file};
}

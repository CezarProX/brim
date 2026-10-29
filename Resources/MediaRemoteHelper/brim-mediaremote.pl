# Runs BrimMediaRemote.dylib inside /usr/bin/perl, an Apple-signed process that
# mediaremoted still serves.
# Usage: /usr/bin/perl brim-mediaremote.pl /abs/path/BrimMediaRemote.dylib [stream]
#   (no mode)  send one command from QS_MR_BUNDLE / QS_MR_COMMAND and exit
#   stream     long-lived: JSON lines for now-playing changes, commands on stdin
# Technique from ungive/mediaremote-adapter (https://github.com/ungive/mediaremote-adapter, BSD 3-Clause).
use strict;
use warnings;
use DynaLoader;

my $library = shift @ARGV or die "library path required\n";
my $mode = shift @ARGV // "send";
die "library must be an absolute path\n" unless $library =~ m{^/};
die "unknown mode\n" unless $mode eq "send" || $mode eq "stream";
my $handle = DynaLoader::dl_load_file($library, 0) or die DynaLoader::dl_error() . "\n";
my $name = $mode eq "stream" ? "brim_mediaremote_stream" : "brim_mediaremote_send";
my $symbol = DynaLoader::dl_find_symbol($handle, $name) or die DynaLoader::dl_error() . "\n";
DynaLoader::dl_install_xsub("main::$name", $symbol);
no strict "refs";
&{"main::$name"}();

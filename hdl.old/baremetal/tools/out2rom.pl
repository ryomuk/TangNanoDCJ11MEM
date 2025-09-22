#!/usr/bin/perl
use strict;
use warnings;

my $file = $ARGV[0];
open my $fh, "<", $file or die $!;
binmode($fh);

my $TOPADDRESS = 01000;
my $ROMSIZE    = 32768;
my $buf;
my $data;
my $lastflag = 0;

print
    "// rom.v\n".
    "// to be included from the top module at the compile\n\n".
    "`define MEM(x, y) {mem_hi[(x)>>1], mem_lo[(x)>>1]}=y\n\n",
    "initial\n".
    "begin\n";


sysread($fh, $buf, 16); # skip header
for(my $addr = 0; $addr < $ROMSIZE; $addr+=2){
    if(sysread($fh, $buf, 2) == 2){
        $data = unpack("S2", $buf);
    } else {
        $data = 0;
	$lastflag = 1;
    }
    printf("`MEM('o%06o, 16'o%06o);\n", $TOPADDRESS+$addr, $data);
    if($lastflag){
	last;
    }
}
print  "end\n";

close $fh;

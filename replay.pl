#!/usr/bin/perl

use strict;
use warnings;

use autodie;

my $START = '60';
my $END = '80';
my $DEMO = 'server/test';
my $WSW_CMD = '/usr/bin/warsow';
my $WSW_DIR = '~/.warsow-0.6/';
my $MOD = 'basewsw';
my $MOD_DIR = $WSW_DIR . $MOD . '/';
my $COMMUNICATION_DIR = $MOD_DIR . 'ipc/gametype/';
my $DEMO_DIR = $MOD_DIR . 'avi/';
my $DISPLAY = 1;
my %COMMANDS = (
    'pause' => ['demopause', 'a'],
    'next' => ['+moveup', 'b'],
    'jump' => ['demojump', 'c'],
    'start' => ['demopause;demojump ' . $START . ';demopause;demoavi', 'd'],
    'check' => ['demotime', 'e'],
    'stop' => ['quit', 'f']
);

#TBD: verify that there is no old footage there

# start warsow
my $arguments = '';
for my $cmd (keys %COMMANDS) {
    $arguments .= ' +bind ' . $COMMANDS{$cmd}->[1] . ' "' . $COMMANDS{$cmd}->[0].'"';
}
$arguments .= ' +demo "' . $DEMO . '"';
open my $pipe, '-|', 'xinit ' . $WSW_CMD . $arguments . ' -- :' . $DISPLAY;
while (my $line = <$pipe>) {
    say $line;
}
close $pipe;

# process the video
#system '';

exit;

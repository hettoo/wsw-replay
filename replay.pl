#!/usr/bin/perl

use strict;
use warnings;
use feature qw(switch state);

use autodie;
use Time::HiRes 'time';

my $START = '60';
my $END = '70';
my $DEMO = 'server/test';
my $WSW_CMD = '/usr/bin/warsow';
my $WSW_DIR = '/home/hettoo/.warsow-0.6/';
my $MOD = 'racesow';
my $MOD_DIR = $WSW_DIR . $MOD . '/';
my $COMMUNICATION_DIR = $MOD_DIR . 'ipc/gametype/';
my $AVI_DIR = $MOD_DIR . 'avi/';
my $VIDEO = 'demo.mp4';
my $SETTINGS = '';
my $SKIP = 2;
my $FPS = 25;
my $WIDTH = 384;
my $HEIGHT = 308;
my $LOG = 'replay';
my $DISPLAY = 1;
my $POLL_SCRIPT = 'replay-poll.cfg';
my $POLL_DELAY = 0.2;
my $CONSOLE_HEIGHT = 4;
open my $out, '>', $MOD_DIR . $POLL_SCRIPT;
print $out 'demotime' . (';echo' x $CONSOLE_HEIGHT);
close $out;
my %COMMANDS = (
    'pause' => ['demopause', 'h'],
    'next' => ['+moveup', 'i'],
    'jump' => , ['demojump ' . $START, 'j'],
    'start' => ['demoavi', 'k'],
    'poll' => ['exec ' . $POLL_SCRIPT . ' silent', 'l'],
    'stop' => ['quit', 'm']
);

my @files;
get_files();
if (@files > 0 || -e $AVI_DIR . $VIDEO) {
    die 'Old footage present';
}
my $needs_poll = 0;
run();
exit;

sub run {
    my $logfile = $MOD_DIR . $LOG . '.log';
    if (-e $logfile) {
        unlink $logfile;
    }
    run_game();
    while (!-e $logfile) {
    }
    my $poll_time = 0;
    open my $log, '<', $logfile;
    my $line;
    do {
        my $pos = tell $log;
        $line = <$log>;
        if (defined $line && $line =~ /\R$/) {
            $line = filter($line);
            process($line);
        } else {
            seek $log, $pos, 0;
        }
        if ($needs_poll) {
            if (time >= $poll_time + $POLL_DELAY) {
                issue_command('poll');
                $poll_time = time;
            }
        }
    } while (!defined $line || $line ne 'Demo completed');
    close $log;
    unlink $MOD_DIR . $POLL_SCRIPT;
    create_video();
}

sub run_game {
    my $arguments = '';
    for my $cmd (keys %COMMANDS) {
        $arguments .= ' "+bind ' . $COMMANDS{$cmd}->[1] . ' ' . $COMMANDS{$cmd}->[0].'"';
    }
    $arguments .= ' +set fs_game ' . $MOD . ' +set r_mode -1 +set vid_customwidth ' . $WIDTH . ' +set vid_customheight ' . $HEIGHT . ' +cl_demoavi_fps ' . $FPS .  ' +logconsole ' . $LOG . ' +logconsole_flush 1 ' . $SETTINGS .' +demo "' . $DEMO . '"';
    system 'xinit ' . $WSW_CMD . $arguments . ' -- :' . $DISPLAY . ' >/dev/null &';
}

sub create_video {
    get_files();
    my @removed = splice @files, 0, $SKIP;
    for my $removed (@removed) {
        unlink $removed;
    }
    system 'ffmpeg -r ' . $FPS . ' -i ' . $AVI_DIR . 'avi%06d.jpg ' . $AVI_DIR . $VIDEO;
    for my $file (@files) {
        unlink $file;
    }
}

sub filter {
    my($arg) = @_;
    if (!defined $arg) {
        return $arg;
    }
    $arg =~ s/\^\d//g;
    chomp $arg;
    return $arg;
}

sub process {
    my($line) = @_;
    print $line . "\n";
    state $started = 0;
    state $stopped = 0;
    if ($stopped) {
        return;
    }
    if ($line =~ /"demotime" is "(\d+)"/) {
        if (!$started) {
            issue_command('pause');
            issue_command('jump');
            issue_command('pause');
            issue_command('start');
            $started = 1;
        } else {
            if ($1 >= $END) {
                issue_command('stop');
                $stopped = 1;
            } else {
                $needs_poll = 1;
            }
        }
    } else {
        $needs_poll = 1;
    }
}

sub issue_command {
    my($command) = @_;
    system 'DISPLAY=:' . $DISPLAY . ' xdotool key ' . $COMMANDS{$command}->[1];
}

sub get_files {
    @files = glob $AVI_DIR . '*.jpg';
}

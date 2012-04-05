#!/usr/bin/perl

use strict;
use warnings;
use feature qw(switch state say);

use autodie;
use Time::HiRes 'time';
use File::Copy;

my $START = '180';
my $END = '240';
my $DEMO = 'server/mp';
my $WSW_CMD = '/usr/bin/warsow';
my $WSW_DIR = '/home/hettoo/.warsow-0.6/';
my $MOD = 'basewsw';
my $MOD_DIR = $WSW_DIR . $MOD . '/';
my $AVI_DIR = $MOD_DIR . 'avi/';
my $VIDEO = 'demo.mp4';
my $SETTINGS = '';
my $OPTIONS = '';
my $SKIP = 7;
my $FPS = 25;
my $PLAYER = 1;
my $WIDTH = 384;
my $HEIGHT = 308;
my $LOG = 'replay';
my $DISPLAY = 1;
my $POLL_SCRIPT = 'replay-poll.cfg';
my $BINDS_SCRIPT = 'replay-binds.cfg';
my $POLL_DELAY = 0.2;
my $CONSOLE_HEIGHT = 4;
my %COMMANDS = (
    'pause' => ['demopause', 'h'],
    'next' => ['+moveup', 'i'],
    'jump' => , ['demojump ' . $START, 'j'],
    'start' => ['demoavi', 'k'],
    'poll' => ['exec ' . $POLL_SCRIPT . ' silent', 'l'],
    'stop' => ['quit', 'm']
);

run();
exit;

sub run {
    open my $shell, '|-', 'bash';
    $shell->autoflush(1);
    check_old_files();
    my $logfile = $MOD_DIR . $LOG . '.log';
    if (-e $logfile) {
        unlink $logfile;
    }
    create_binds_script();
    create_poll_script();
    run_game($shell);
    while (!-e $logfile) {
    }
    my $needs_poll = 0;
    my $poll_time = 0;
    open my $log, '<', $logfile;
    my $line;
    do {
        my $pos = tell $log;
        $line = <$log>;
        if (defined $line && $line =~ /\R$/) {
            $line = filter($line);
            if (process($line)) {
                $needs_poll = 1;
            }
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
    say $shell 'kill %1';
    close $shell;
    unlink $MOD_DIR . $POLL_SCRIPT;
    unlink $MOD_DIR . $BINDS_SCRIPT;
    create_video();
}

sub check_old_files {
    my @files = get_files();
    if (@files > 0 || -e $AVI_DIR . $VIDEO) {
        die 'Old footage present';
    }
}

sub create_binds_script {
    my $binds = '';
    for my $cmd (keys %COMMANDS) {
        $binds .= 'bind ' . $COMMANDS{$cmd}->[1] . ' "' . $COMMANDS{$cmd}->[0].'";';
    }
    open my $out, '>', $MOD_DIR . $BINDS_SCRIPT;
    print $out $binds;
    close $out;
}

sub create_poll_script {
    open my $out, '>', $MOD_DIR . $POLL_SCRIPT;
    print $out 'demotime' . (';echo' x $CONSOLE_HEIGHT);
    close $out;
}

sub run_game {
    my($shell) = @_;
    my $arguments = ' +set fs_game ' . $MOD . ' +set r_mode -1 +set vid_customwidth ' . $WIDTH . ' +set vid_customheight ' . $HEIGHT . ' +cl_demoavi_fps ' . $FPS .  ' +logconsole ' . $LOG . ' +logconsole_flush 1 +exec ' . $BINDS_SCRIPT . ' +cg_showFPS 0 ' . $SETTINGS .' +demo "' . $DEMO . '"';
    say $shell 'xinit ' . $WSW_CMD . $arguments . ' -- :' . $DISPLAY . ' >/dev/null &';
}

sub create_video {
    my @files = get_files();
    for my $i (0 .. $#files - $SKIP) {
        move($files[$i + $SKIP], $files[$i]);
    }
    @files = get_files();
    my $wanted = $FPS * ($END - $START);
    if ($wanted < @files) {
        my @removed = splice @files, int $wanted + 0.5;
        for my $removed (@removed) {
            unlink $removed;
        }
    }
    system 'ffmpeg -r ' . $FPS . ' ' . $OPTIONS . ' -i ' . $AVI_DIR . 'avi%06d.jpg ' . $AVI_DIR . $VIDEO;
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
    state $started = 0;
    state $switched = 0;
    state $stopped = 0;
    if ($stopped) {
        return 0;
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
                if (!$switched) {
                    for (0 .. $PLAYER - 1) {
                        issue_command('next');
                    }
                    $switched = 1;
                }
                return 1;
            }
        }
    } else {
        return 1;
    }
    return 0;
}

sub issue_command {
    my($command) = @_;
    system 'DISPLAY=:' . $DISPLAY . ' xdotool key ' . $COMMANDS{$command}->[1];
}

sub get_files {
    return glob $AVI_DIR . '*.jpg';
}

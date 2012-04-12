#!/usr/bin/perl

use strict;
use warnings;
use feature qw(switch state say);

use autodie;
use Time::HiRes 'time';
use File::Copy;

my $start = '180';
my $end = '240';
my $demo = 'server/mp';
my $game_cmd = '/usr/bin/warsow';
my $game_dir = $ENV{'HOME'} . '/.warsow-0.6/';
my $mod = 'basewsw';
my $game_settings = '';
my $video_settings = '';
my $skip = 7;
my $fps = 25;
my $width = 384;
my $height = 308;
my $display = 1;

my $NAME = 'replay';
my $MOD_DIR = $game_dir . $mod . '/';
my $AVI_DIR = $MOD_DIR . 'avi/';
my $LOG = $NAME;
my $POLL_DELAY = 0.5;
my $CONSOLE_HEIGHT = 4;
my $VIDEO = 'demo.mp4';
my $POLL_SCRIPT = $NAME . '-poll.cfg';
my $BINDS_SCRIPT = $NAME . '-binds.cfg';
my %COMMANDS = (
    'pause' => ['demopause', 'h'],
    'jump' => , ['demojump ' . $start, 'i'],
    'start' => ['demoavi', 'j'],
    'poll' => ['exec ' . $POLL_SCRIPT . ' silent', 'l'],
    'stop' => ['quit', 'm']
);
my @DEPENDENCIES = ($game_cmd, 'xinit', 'xdotool', 'ffmpeg');

test_dependencies();
read_options();
check_options();
run();
exit;

sub test_dependencies {
    for my $dependency (@DEPENDENCIES) {
        if ((substr $dependency, 0, 1 eq '/' && !-e $dependency)
            || system 'which ' . $dependency . ' &>/dev/null') {
            die 'Dependency ' . $dependency . " not found\n";
        }
    }
}

sub read_options {
}

sub check_options {
}

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
        $binds .= 'bind ' . $COMMANDS{$cmd}->[1]
            . ' "' . $COMMANDS{$cmd}->[0].'";';
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
    my $arguments = ' +set fs_game ' . $mod
        . ' +set r_mode -1'
        . ' +set vid_customwidth ' . $width
        . ' +set vid_customheight ' . $height
        . ' +set cl_demoavi_fps ' . $fps
        . ' +set logconsole ' . $LOG
        . ' +set logconsole_flush 1'
        . ' +set cg_showFPS 0 '
        . ' +exec ' . $BINDS_SCRIPT
        . $game_settings
        . ' +demo "' . $demo . '"';
    say $shell 'xinit ' . $game_cmd . $arguments . ' -- :' . $display
        . ' >/dev/null &';
}

sub create_video {
    my @files = get_files();
    for my $i (0 .. $#files - $skip) {
        move($files[$i + $skip], $files[$i]);
    }
    @files = get_files();
    my $wanted = $fps * ($end - $start);
    if ($wanted < @files) {
        my @removed = splice @files, int $wanted + 0.5;
        for my $removed (@removed) {
            unlink $removed;
        }
    }
    system 'ffmpeg -r ' . $fps . ' ' . $video_settings
        . ' -i ' . $AVI_DIR . 'avi%06d.jpg ' . $AVI_DIR . $VIDEO;
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
            if ($1 >= $end) {
                issue_command('stop');
                $stopped = 1;
            } else {
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
    system 'DISPLAY=:' . $display . ' xdotool key ' . $COMMANDS{$command}->[1];
}

sub get_files {
    return glob $AVI_DIR . '*.jpg';
}

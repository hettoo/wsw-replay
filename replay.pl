#!/usr/bin/perl

use strict;
use warnings;
use feature qw(switch say);

use autodie;
use Getopt::Long;
use Time::HiRes 'time';
use File::Copy;

my(
    $NAME, $MOD_DIR, $AVI_DIR, $LOG, $POLL_DELAY, $CONSOLE_HEIGHT,
    $VIDEO, $AUDIO, $POLL_SCRIPT, $BINDS_SCRIPT, %COMMANDS, @DEPENDENCIES
);

my $demo;
my $start = 0;
my $end = 0;
my $audio = 0;
my $game_cmd = '/usr/bin/warsow';
my $game_dir = $ENV{'HOME'} . '/.warsow-0.6/';
my $mod = 'basewsw';
my $game_settings = '';
my $video_settings = '';
my $skip = 0;
my $fps = 50;
my $width = 1280;
my $height = 720;
my $display = 1;

get_options();
set_constants();
test_dependencies();
run();
exit;

sub get_options {
    GetOptions(
        'start=i' => \$start,
        'end=i' => \$end,
        'audio' => \$audio,
        'game=s' => \$game_cmd,
        'dir=s' => \$game_dir,
        'mod=s' => \$mod,
        'game-settings=s' => \$game_settings,
        'video-settings=s' => \$video_settings,
        'skip=i' => \$skip,
        'fps=i' => \$fps,
        'width=i' => \$width,
        'height=i' => \$height,
        'display=i' => \$display,
        'help' => \&help
    );
    if (@ARGV == 1) {
        $demo = $ARGV[0];
    } else {
        help();
    }
}

sub help {
    say 'Usage: ' . $0 . ' [OPTION]... demo';
    say 'Render a Warsow game demo.';
    say '';
    say '  --start=SECOND              set the start second';
    say '  --end=SECOND                set the end second';
    say '  --audio                     also render audio';
    say '  --game=COMMAND              set the game command';
    say '  --dir=DIR                   set the game directory (for this user)';
    say '  --mod=MOD                   set the game mod';
    say '  --game-settings=SETTINGS    set additional game settings';
    say '  --video-settings=SETTINGS   set additional video settings';
    say '  --skip=FRAMES               remove the first FRAMES frames';
    say '  --fps=FPS                   set the fps';
    say '  --width=PIXELS              set the width';
    say '  --height=PIXELS             set the height';
    say '  --display=DISPLAY           set the X display to use';
    say '  --help                      display this help and exit';
    exit;
}

sub set_constants {
    $NAME = 'replay';
    $MOD_DIR = $game_dir . $mod . '/';
    $AVI_DIR = $MOD_DIR . 'avi/';
    $LOG = $NAME;
    $POLL_DELAY = 0.5;
    $CONSOLE_HEIGHT = 4;
    $VIDEO = 'demo.mp4';
    $AUDIO = 'wavdump.wav';
    $POLL_SCRIPT = $NAME . '-poll.cfg';
    $BINDS_SCRIPT = $NAME . '-binds.cfg';
    %COMMANDS = (
        'pause' => ['demopause', 'h'],
        'jump' => , ['demojump ' . $start, 'i'],
        'start' => ['demoavi', 'j'],
        'poll' => ['exec ' . $POLL_SCRIPT . ' silent', 'l'],
        'stop' => ['quit', 'm']
    );
    @DEPENDENCIES = ($game_cmd, 'xinit', 'xdotool', 'ffmpeg');
}

sub test_dependencies {
    my $fail = '';
    for my $dependency (@DEPENDENCIES) {
        if ((substr $dependency, 0, 1 eq '/' && !-e $dependency)
            || system 'which ' . $dependency . ' &>/dev/null') {
            $fail .= 'Dependency ' . $dependency . ' not found' . "\n";
        }
    }
    if ($fail ne '') {
        die $fail;
    }
}

sub run {
    open my $shell, '|-', 'bash';
    $shell->autoflush(1);
    check_old_files();
    create_binds_script();
    create_poll_script();
    get_images($shell);
    if ($audio) {
        flush_jobs($shell);
        get_audio($shell);
    }
    close $shell;
    unlink $MOD_DIR . $POLL_SCRIPT;
    unlink $MOD_DIR . $BINDS_SCRIPT;
    create_video();
}

sub check_old_files {
    my @files = get_files();
    if (@files > 0 || -e $AVI_DIR . $VIDEO || -e $AVI_DIR . $AUDIO) {
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

sub get_images {
    my($shell) = @_;
    run_game_wrapped($shell, '+set cl_demoavi_video 1 +set cl_demoavi_audio 0'
        . ' +set r_screenshot_jpeg 1');
}

sub get_audio {
    my($shell) = @_;
    run_game_wrapped($shell, '+set cl_demoavi_video 0 +set cl_demoavi_audio 1'
        . ' +set s_module 1');
}

sub flush_jobs {
    my($shell) = @_;
    say $shell 'while kill `jobs -p` >/dev/null; do true; done;';
}

sub run_game_wrapped {
    my($shell, $extra_settings) = @_;
    my $logfile = $MOD_DIR . $LOG . '.log';
    if (-e $logfile) {
        unlink $logfile;
    }
    run_game($shell, $extra_settings);
    while (!-e $logfile) {
    }
    my $started = 0;
    my $stopped = 0;
    my $needs_poll = 0;
    my $poll_time = 0;
    open my $log, '<', $logfile;
    my $line;
    do {
        my $pos = tell $log;
        $line = <$log>;
        if (defined $line && $line =~ /\R$/) {
            $line = filter($line);
            process($line, \$started, \$stopped, \$needs_poll);
        } else {
            seek $log, $pos, 0;
        }
        if ($needs_poll) {
            if (time >= $poll_time + $POLL_DELAY) {
                issue_command('poll');
                $poll_time = time;
                $needs_poll = 0;
            }
        }
    } while (!defined $line || $line ne 'Demo completed');
    close $log;
    say $shell 'kill `jobs -p`';
}

sub run_game {
    my($shell, $extra_settings) = @_;
    my $arguments = ' +set fs_game ' . $mod
        . ' +set r_mode -1'
        . ' +set vid_customwidth ' . $width
        . ' +set vid_customheight ' . $height
        . ' +set cl_demoavi_fps ' . $fps
        . ' +set logconsole ' . $LOG
        . ' +set logconsole_flush 1'
        . ' +set cg_showFPS 0 '
        . ' +exec ' . $BINDS_SCRIPT
        . ' ' . $extra_settings
        . ' ' . $game_settings
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
    if ($end > 0) {
        my $wanted = $fps * ($end - $start);
        if ($wanted < @files) {
            my @removed = splice @files, int $wanted + 0.5;
            for my $removed (@removed) {
                unlink $removed;
            }
        }
    }
    system 'ffmpeg -r ' . $fps . ' ' . $video_settings
        . ' -i ' . $AVI_DIR . 'avi%06d.jpg '
        . ($audio ? '-i ' . $AVI_DIR . $AUDIO . ' -acodec libmp3lame ' : '')
        . $AVI_DIR . $VIDEO;
    for my $file (@files) {
        unlink $file;
    }
    unlink $AVI_DIR . $AUDIO;
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
    my($line, $started, $stopped, $needs_poll) = @_;
    if (${$stopped}) {
        return;
    }
    if ($line =~ /"demotime" is "(\d+)"/) {
        if (!${$started}) {
            issue_command('pause');
            issue_command('jump');
            issue_command('pause');
            issue_command('start');
            ${$started} = 1;
        } else {
            if ($end > 0 && $1 >= $end) {
                issue_command('stop');
                ${$stopped} = 1;
            } else {
                ${$needs_poll} = 1;
            }
        }
    } else {
        ${$needs_poll} = 1;
    }
}

sub issue_command {
    my($command) = @_;
    system 'DISPLAY=:' . $display . ' xdotool key ' . $COMMANDS{$command}->[1];
}

sub get_files {
    return glob $AVI_DIR . '*.jpg';
}

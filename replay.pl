#!/usr/bin/perl

use strict;
use warnings;
use feature qw(switch say);

use autodie;
use Getopt::Long;
use POSIX 'ceil';
use Time::HiRes 'time';
use File::Copy;

# Global 'constants'
my(
    $NAME, $MOD_DIR, $AVI_DIR, $LOG, $POLL_DELAY, $CONSOLE_HEIGHT,
    $VIDEO, $AUDIO, $POLL_SCRIPT, $BINDS_SCRIPT, %COMMANDS, @DEPENDENCIES
);

# Options
my $demo;
my $start = 0;
my $end = 0;
my $audio = 0;
my $game_cmd = '/usr/bin/warsow';
my $game_dir = $ENV{'HOME'} . '/.warsow-0.6/';
my $mod = 'basewsw';
my $player = 0;
my $game_settings = '';
my $video_settings = '';
my $skip = 0;
my $fps = 50;
my $width = 1280;
my $height = 720;
my $display = 1;

# Other global variables
my $shell;

# Main program
get_options();
set_constants();
test_dependencies();
replay();
exit;

# Processes command line input.
sub get_options {
    GetOptions(
        'start=f' => \$start,
        'end=f' => \$end,
        'audio' => \$audio,
        'game=s' => \$game_cmd,
        'dir=s' => \$game_dir,
        'mod=s' => \$mod,
        'player=i' => \$player,
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

# Display a help screen and exit.
sub help {
    say 'Usage: ' . $0 . ' [OPTION]... demo';
    say 'Render a Warsow game demo.';
    say '';
    say '  --start=SECOND              start at second SECOND';
    say '  --end=SECOND                end at second SECOND';
    say '  --audio                     also render audio';
    say '  --game=COMMAND              set the game executable to COMMAND';
    say '  --dir=DIR                   set the game directory (for this user)'
        . ' to DIR';
    say '  --mod=MOD                   set the game mod to MOD';
    say '  --player=NUMBER             skips NUMBER players before recording';
    say '  --game-settings=SETTINGS    set additional game settings SETTINGS';
    say '  --video-settings=SETTINGS   set additional ffmpeg settings SETTINGS';
    say '  --skip=FRAMES               remove the first FRAMES frames';
    say '  --fps=FPS                   render at FPS fps';
    say '  --width=PIXELS              render with a width of PIXELS';
    say '  --height=PIXELS             render with a height of PIXELS';
    say '  --display=DISPLAY           use X display DISPLAY';
    say '  --help                      display this help and exit';
    exit;
}

# Initializes the 'constants'.
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
        'jump' => ['demojump ' . $start, 'i'],
        'jump-preskip' => ['demojump ' . ($start + $skip / $fps), 'j'],
        'next' => ['weapnext', 'l'],
        'start' => ['demoavi', 'm'],
        'poll' => ['exec ' . $POLL_SCRIPT . ' silent', 'n'],
        'stop' => ['quit', 'o']
    );
    @DEPENDENCIES = ($game_cmd, 'xinit', 'xdotool', 'ffmpeg');
}

# Tests if all dependencies are available.
sub test_dependencies {
    my $fail = '';
    for my $dependency (@DEPENDENCIES) {
        if ((substr $dependency, 0, 1 eq '/' && !-e $dependency)
            || system 'which ' . $dependency . ' &>/dev/null') {
            $fail .= "Dependency $dependency not found\n";
        }
    }
    if ($fail ne '') {
        die $fail;
    }
}

# Converts the demo to a video.
sub replay {
    open $shell, '|-', 'bash';
    $shell->autoflush(1);
    check_old_files();
    create_binds_script();
    create_poll_script();
    render_images();
    if ($audio) {
        flush_jobs();
        render_audio();
    }
    close $shell;
    unlink $MOD_DIR . $POLL_SCRIPT;
    unlink $MOD_DIR . $BINDS_SCRIPT;
    create_video();
}

# Checks if there is no old footage present.
sub check_old_files {
    my @images = get_images();
    if (@images > 0 || -e $AVI_DIR . $VIDEO || -e $AVI_DIR . $AUDIO) {
        die "Old footage present\n";
    }
}

# Creates a .cfg file containing the needed keybinds.
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

# Creates a .cfg file for polling the demotime.
sub create_poll_script {
    open my $out, '>', $MOD_DIR . $POLL_SCRIPT;
    print $out 'demotime' . (';echo' x $CONSOLE_HEIGHT);
    close $out;
}

# Renders the video images.
sub render_images {
    run_game_wrapped('+set cl_demoavi_video 1 +set cl_demoavi_audio 0'
        . ' +set r_screenshot_jpeg 1', 0);
}

# Renders the video audio.
sub render_audio {
    run_game_wrapped('+set cl_demoavi_video 0 +set cl_demoavi_audio 1'
        . ' +set s_module 1', 1);
}

# Makes sure all jobs have ended before new commands are executed on the shell.
sub flush_jobs {
    say $shell 'while kill `jobs -p` &>/dev/null; do true; done';
}

# Runs the game and communicates with it to make it record the needed parts and
# exit.
sub run_game_wrapped {
    my($extra_settings, $preskip) = @_;
    my $logfile = $MOD_DIR . $LOG . '.log';
    if (-e $logfile) {
        unlink $logfile;
    }
    run_game($extra_settings);
    while (!-e $logfile) { }
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
            if ($line =~ /^error: (.+)/i
                || $line =~ /(no valid demo file found)/i) {
                flush_jobs();
                die "Warsow error: $1\n";
            }
            process($line, \$started, \$stopped, \$needs_poll, $preskip);
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

# Runs the game.
sub run_game {
    my($extra_settings) = @_;
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
        . ' &>/dev/null &';
}

# Turns the generated footage into one video file and removes the intermediate
# files.
sub create_video {
    my @images = get_images();
    if ($end > 0) {
        my $wanted = $fps * ($end - $start);
        if ($wanted < @images) {
            my @removed = splice @images, ceil($wanted);
            for my $removed (@removed) {
                unlink $removed;
            }
        }
    }
    for my $i (0 .. $#images - $skip) {
        move($images[$i + $skip], $images[$i]);
    }
    splice @images, @images - $skip;
    system 'ffmpeg -r ' . $fps
        . ($end > 0 ? ' -t ' . ($end - $start) : '')
        . ' -i ' . $AVI_DIR . 'avi%06d.jpg'
        . ($audio ? ' -i ' . $AVI_DIR . $AUDIO . ' -acodec libmp3lame' : '')
        . ' ' . $video_settings
        . ' ' . $AVI_DIR . $VIDEO;
    for my $image (@images) {
        unlink $image;
    }
    if ($audio) {
        unlink $AVI_DIR . $AUDIO;
    }
}

# Filters a string from colortokens and chomps it.
sub filter {
    my($arg) = @_;
    if (!defined $arg) {
        return $arg;
    }
    $arg =~ s/\^\d//g;
    chomp $arg;
    return $arg;
}

# Acts on an input line from the game.
sub process {
    my($line, $started, $stopped, $needs_poll, $preskip) = @_;
    if (${$stopped}) {
        return;
    }
    if ($line =~ /"demotime" is "(\d+)"/) {
        if (!${$started}) {
            issue_command('pause');
            if ($preskip) {
                issue_command('jump-preskip');
            } else {
                issue_command('jump');
            }
            for (1 .. $player) {
                issue_command('next');
            }
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

# Makes the game execute a predefined command.
sub issue_command {
    my($command) = @_;
    system 'DISPLAY=:' . $display . ' xdotool key ' . $COMMANDS{$command}->[1];
}

# Returns an array of Warsow-generated demo image files.
sub get_images {
    return glob $AVI_DIR . '*.jpg';
}

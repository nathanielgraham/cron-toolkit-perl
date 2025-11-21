#!/usr/bin/env perl
# t/quartz_verify.t - Full verification with nice output
use strict;
use warnings;
use lib 'lib';
use JSON::PP;
use Time::Moment;
use Term::ANSIColor qw(colored);
use Cron::Toolkit;

my $json = do { local $/; open my $fh, '<', 't/data/cron_tests.json' or die "Cannot open json: $!"; <$fh> };
my $tests = decode_json($json);

my $total = 0;
my $failed = 0;

for my $t (@$tests) {
    next if $t->{invalid};

    $total++;

    my $ok = 1;
    my $c;

    eval {
        $c = Cron::Toolkit->new(expression => $t->{expr});
        $c->time_zone($t->{tz}) if $t->{tz};
        $c->utc_offset($t->{utc_offset}) if exists $t->{utc_offset};
    };
    if ($@) {
        print colored("not ok - $t->{expr} (construction failed: $@)\n", 'red');
        $ok = 0;
        next;
    }

    print "\n=== $t->{expr} ===\n";

    # as_string
    my $as_string = $c->as_string;
    print "as_string:        $as_string\n";
    $ok = 0 if $as_string ne $t->{as_string};

    # dump_tree
    print "dump_tree:\n" . $c->dump_tree . "\n";

    # as_quartz_string
    my $quartz = $c->as_quartz_string;
    print "as_quartz_string: $quartz\n";
    $ok = 0 if $quartz ne $t->{as_quartz_string};

    # describe
    my $desc = $c->describe;
    print "describe:         $desc\n";

    # next / previous
    my $base = $t->{base_epoch};
    my $next = $c->next($base);
    my $prev = $c->previous($base);

    print "next (from " . scalar gmtime($base) . "):   " . ($next // 'undef') . "\n";
    print "prev:                                 " . ($prev // 'undef') . "\n";

    $ok = 0 if $next != $t->{next_epoch};
    $ok = 0 if $prev != $t->{prev_epoch};

    if ($ok) {
        print colored("ok\n", 'green');
    } else {
        print colored("not ok\n", 'red');
        $failed++;
    }
}

print "\nSummary: $total tests, " . ($total - $failed) . " passed, $failed failed\n";
exit($failed ? 1 : 0);

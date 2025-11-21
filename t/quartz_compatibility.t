#!/usr/bin/env perl
# t/quartz_compatibility.t
use strict;
use warnings;
use Test::More;
use JSON::PP;
use Time::Moment;
use lib 'lib';
use Cron::Toolkit;

my $json = do { local $/; open my $fh, '<', 't/data/cron_tests.json'; <$fh> };
my $tests = decode_json($json);

plan tests => scalar(@$tests) * 6;  # 6 checks per test

for my $t (@$tests) {
    next if $t->{invalid};

    my $c;
    eval {
        $c = Cron::Toolkit->new(expression => $t->{expr});
        if (exists $t->{tz} && defined $t->{tz}) {
            $c->time_zone($t->{tz});
        }
        if (exists $t->{utc_offset} && defined $t->{utc_offset}) {
            $c->utc_offset($t->{utc_offset});
        }
    };
    if ($@) {
        fail("$t->{expr} - construction failed: $@");
        next;
    }

    is($c->as_string, $t->{as_string}, "$t->{expr} - as_string");
    is($c->as_quartz_string, $t->{as_quartz_string}, "$t->{expr} - as_quartz_string");

    my $base = $t->{base_epoch};
    my $next = $c->next($base);
    my $prev = $c->previous($base);

    is($next, $t->{next_epoch}, "$t->{expr} - next() from " . scalar gmtime($base));
    is($prev, $t->{prev_epoch}, "$t->{expr} - previous() from " . scalar gmtime($base));

    like($c->describe, qr/^\w/, "$t->{expr} - describe() returns something");

    diag "\n=== $t->{expr} ===\n" . $c->dump_tree . "\n" if $ENV{VERBOSE};
}

done_testing;

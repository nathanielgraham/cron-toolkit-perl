#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Cron::Toolkit;
use Time::Moment;
use Data::Dumper;

# Base time: Floor now_utc to minute for clean tests
my $base = Time::Moment->now_utc;
#$base = $base->plus_seconds(-$base->second)->plus_minutes(-$base->minute);
my $base_epoch = $base->epoch;
diag "Base time: " . $base->strftime('%Y-%m-%d %H:%M:%S UTC') . " (epoch $base_epoch)";

my @tests = (
    {
        expr => '0 0 0 ? * 3#3 *',
        desc => 'nth third',
        next_tm => $base->plus_seconds(1),
        prev_tm => $base->minus_seconds(1),
    },
    {
        expr => '* * * ? 2 1#5 *',
        desc => 'nth third',
        next_tm => $base->plus_seconds(1),
        prev_tm => $base->minus_seconds(1),
    },

    {
        expr => '0 0 0 16W * ? *',
        desc => 'nearest weekday',
        next_tm => $base->plus_seconds(1),
        prev_tm => $base->minus_seconds(1),
    },
    {
        expr => '* * * 8 * 2#2 *',
        desc => 'dow dom',
        next_tm => $base->plus_seconds(1),
        prev_tm => $base->minus_seconds(1),
    },
    {
        expr => '* * 16-20 * * ? *',
        desc => 'every second',
        next_tm => $base->plus_seconds(1),
        prev_tm => $base->minus_seconds(1),
    },
    {
        expr => '14/5 * * * * ? *',
        desc => 'every second',
        next_tm => $base->plus_seconds(1),
        prev_tm => $base->minus_seconds(1),
    },
    {
        expr => '21 * * * * ? *',
        desc => 'every minute',
        next_tm => $base->plus_minutes(1),
        prev_tm => $base->minus_minutes(1),
    },
    {
        expr => '* 21 * * * ? *',
        desc => 'every minute',
        next_tm => $base->plus_minutes(1),
        prev_tm => $base->minus_minutes(1),
    },
    {
        expr => '* * 2 * * ? *',
        desc => 'every minute',
        next_tm => $base->plus_minutes(1),
        prev_tm => $base->minus_minutes(1),
    },
    {
        expr => '0 3/4 * * * ? *',
        desc => 'every hour at :01',
        next_tm => $base->plus_hours(1)->with_minute(0),
        prev_tm => $base->minus_hours(1)->with_minute(0),
    },
    {
        expr => '0 0 0 * * ? *',
        desc => 'daily at midnight',
        next_tm => $base->plus_days(1)->with_hour(0)->with_minute(0),
        prev_tm => $base->minus_days(1)->with_hour(0)->with_minute(0),
    },
    {
        expr => '0 0 3-4 * * 3 *',  # Tuesday (Unix DOW 2)
        desc => 'every hour on Tuesday',
        next_tm => $base->plus_days(7)->with_hour(1)->with_minute(0),
        prev_tm => $base->minus_days(7)->with_hour(1)->with_minute(0),
    },
    {
        expr => '0 0 0 * * 4 2099',  # Tuesday (Unix DOW 2)
        desc => 'every Tuesday at midnight',
        next_tm => $base->plus_days(7)->with_hour(0)->with_minute(0),
        prev_tm => $base->minus_days(7)->with_hour(0)->with_minute(0),
    },
    {
        expr => '0 4 0 5 * ? 2026',
        desc => 'fifth of every month at midnight',
        next_tm => $base->plus_months(1)->with_day_of_month(1)->with_hour(0)->with_minute(0),
        prev_tm => $base->with_day_of_month(1)->with_hour(0)->with_minute(0),
    },
    {
        expr => '1 0 0 29 2 ? *',
        desc => 'last day of month at midnight (Quartz)',
    },
    {
        expr => '*/15 * * * * ?',
        desc => 'every 15 seconds',
        next_tm => $base->plus_seconds(15 - ($base->second % 15) || 15),
        prev_tm => $base->minus_seconds(($base->second % 15) || 15),
    },
);

#plan tests => scalar(@tests) * 2;

foreach my $t (@tests) {
    my $cron = Cron::Toolkit->new(expression => $t->{expr});
    diag "Testing: $t->{desc} (" . $cron->as_string . ")";

    #print $cron->dump_tree;
    print Dumper($cron->{raw_fields});
    #print $cron->dump_tree . "\n";
    # next()
    my $next_epoch = $cron->next($base_epoch);
    if ($next_epoch) {
       #print "DESCRIPTION: " . $cron->describe . "\n";
       print "BASE: " . $base->strftime('%Y-%m-%d %H:%M:%S UTC') . "\n";
       print "NEXT: " . scalar gmtime($next_epoch) . " -- $next_epoch\n";
    }
    else {
       print "not found\n";
    }

    #my $next_expected = $t->{next_tm}->epoch;
    #is($next_epoch, $next_expected, "next() for $t->{desc}")
    #    or diag "  Got: " . ($next_epoch ? Time::Moment->from_epoch($next_epoch)->strftime('%Y-%m-%d %H:%M:%S') : 'undef') . 
    #            "\n  Expected: " . $t->{next_tm}->strftime('%Y-%m-%d %H:%M:%S') . " (epoch $next_expected)";

    # previous()
    my $prev_epoch = $cron->previous($base_epoch);
    if ($prev_epoch) {
       print "BASE: " . $base->strftime('%Y-%m-%d %H:%M:%S UTC') . "\n";
       print "PREV: " . scalar gmtime($prev_epoch) . " -- $prev_epoch\n";
    }
    else {
       print "not found\n";
    }
    #use Data::Dumper;
    #my $nextn = $cron->next_n($base_epoch, 3);
    #print Dumper([ map { scalar gmtime $_ } @$nextn ]);
    #print Dumper($nextn);

    #    or diag "  Got: " . ($next_epoch ? Time::Moment->from_epoch($next_epoch)->strftime('%Y-%m-%d %H:%M:%S') : 'undef') . 
    #my $prev_expected = $t->{prev_tm}->epoch;
    #is($prev_epoch, $prev_expected, "previous() for $t->{desc}")
    #    or diag "  Got: " . ($prev_epoch ? Time::Moment->from_epoch($prev_epoch)->strftime('%Y-%m-%d %H:%M:%S') : 'undef') . 
    #            "\n  Expected: " . $t->{prev_tm}->strftime('%Y-%m-%d %H:%M:%S') . " (epoch $prev_expected)";
}

done_testing;

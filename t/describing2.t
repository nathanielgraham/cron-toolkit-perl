#!/usr/bin/env perl
use strict;
use warnings;
use Test::More 0.88;
use Cron::Toolkit;
use JSON::MaybeXS;
use Data::Dumper;

open my $fh, '<', 't/data/cron_tests.json' or BAIL_OUT("JSON missing");
my $json = do { local $/; <$fh> };
my @tests = @{ JSON::MaybeXS->new->decode($json) };

# Add complex diagnostic cases
push @tests, (
    { expr => '0 10-50/10 9-17 * * 1-5 *', desc => 'Business hours, every 10 min from :10 to :50' },
    { expr => '0 0 0 1-5,15,25 * ? *', desc => '1st-5th, 15th, 25th at midnight' },
    { expr => '0 0 8-17/2 * * 1-5 *', desc => 'Every 2 hours from 8AM to 5PM, weekdays' },
    { expr => '0 0 0 L-1 * ? *', desc => 'Second to last day of month' },
    { expr => '0 0 0 15W * ? *', desc => 'Nearest weekday to 15th' },
    { expr => '0 0 0 ? * 2#3 *', desc => 'Third Tuesday' },
    { expr => '0 0 0 1 * 1#1 *', desc => 'First Monday of month' },
    { expr => '*/15 * * * * ? *', desc => 'Every 15 seconds' },
    { expr => '0 */5 * 1-15 * ? *', desc => 'Every 5 min, first half of month' },
    { expr => '0 0 9,12,15 * * ? *', desc => '9AM, 12PM, 3PM daily' },
    { expr => '0 30 14 ? * MON-FRI *', desc => '2:30 PM weekdays' },
    { expr => '0 0 0 ? JAN-MAR,JUN-SEP * *', desc => 'Q1 and Q3' },
    { expr => '0 0 0 * * ? 2025-2030', desc => '2025 to 2030' },
    { expr => '0 0 0 29 2 ? 2024', desc => 'Feb 29 in 2024' },
    { expr => '0 0 0 ? * 1,3,5 *', desc => 'Mon, Wed, Fri' },
    { expr => '0 0 0 L * ? 2025', desc => 'Last day of each month in 2025' },
    { expr => '0 0 0 ? * 1#5 *', desc => 'Fifth Sunday' },
    { expr => '0 0 0 1-31/7 * ? *', desc => 'Every 7th day starting 1st' },
    { expr => '0 0 0 ? * L *', desc => 'Last Saturday' },
    { expr => '0 0 0 10W * ? *', desc => 'Nearest weekday to 10th' },
);

my @valid_desc = grep { !$_->{invalid} && ($_->{desc} || 1) } @tests;

for my $test (@valid_desc) {
    my $cron = Cron::Toolkit->new( expression => $test->{expr} );
    #if ( $test->{tz} ) { $cron->time_zone( $test->{tz} ); }

    #print Dumper($cron->{fields});
    print $cron->as_string . "\n";
    print $cron->dump_tree('') . "\n\n";
    print $cron->describe . "\n\n";
}

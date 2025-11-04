#!/usr/bin/env perl
use strict;
use warnings;
use Test::More 0.88;
use Cron::Toolkit;
use JSON::MaybeXS;
open my $fh, '<', 't/data/cron_tests.json' or BAIL_OUT("JSON missing");
my $json       = do { local $/; <$fh> };
my @tests      = @{ JSON::MaybeXS->new->decode($json) };
my @valid_desc = grep { !$_->{invalid} && $_->{desc} } @tests;

for my $test (@valid_desc) {
   my $cron = Cron::Toolkit->new( expression => $test->{expr} );
   if ( $test->{tz} ) { $cron->time_zone( $test->{tz} ); }
   print $cron->as_string . "\n";
   print $cron->dump_tree . "\n";
   print $cron->describe . "\n\n";
}

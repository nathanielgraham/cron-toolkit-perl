use Test::More;
use JSON::MaybeXS;
use Cron::Toolkit;
use Time::Moment;
use Data::Dumper;

open my $fh, '<', 't/data/cron_tests.json' or die $!;
my $json = do { local $/; <$fh> };
my @tests = @{ JSON::MaybeXS->new->decode($json) };

plan tests => scalar(@tests) * 4;   # next, prev, next_n(3), bounds

for my $t (@tests) {
    next if $t->{invalid};

    my $cron = Cron::Toolkit->new(expression => $t->{expr});
    $cron->time_zone($t->{tz})          if $t->{tz};
    $cron->utc_offset($t->{utc_offset}) if $t->{utc_offset};

    #print Dumper($t);
    # ---- is_match ----
    if ($t->{match}{epoch}) {
       print Dumper($t);
       print Dumper($cron->{nodes});
       my $date = scalar gmtime($t->{match}{epoch});
       my $match = $cron->is_match($t->{match}{epoch});
       #print STDERR "AS_STRING: " . $cron->as_string . "\n";
       print STDERR "MATCH: $match\n";
       is($match, $t->{match}{is_match}, "$date is_match for " . $cron->as_string);
    }

=pod
    # ---- next ----
    my $next = $cron->next;
    is($next, $t->{schedule}{next_epoch}, "next for $t->{expr}");

    # ---- previous ----
    my $prev = $cron->previous;
    is($prev, $t->{schedule}{prev_epoch}, "prev for $t->{expr}");

    # ---- next_n ----
    my $n3 = $cron->next_n(undef, 3);
    is_deeply($n3, $t->{schedule}{next_n}, "next_n[3] for $t->{expr}");

    # ---- bounds (if defined) ----
    if (defined $t->{schedule}{begin_epoch} && defined $t->{schedule}{end_epoch}) {
        $cron->begin_epoch($t->{schedule}{begin_epoch});
        $cron->end_epoch($t->{schedule}{end_epoch});
        my $after = $cron->next($t->{schedule}{end_epoch} + 1);
        ok(!defined $after, "respects end_epoch");
    }
=cut
}

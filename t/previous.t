# t/previous.t
use strict;
use warnings;
use Test::More;
use Cron::Toolkit;
use Time::Moment;

my $base = Time::Moment->from_string('2025-11-02T18:27:23Z');
my $base_epoch = $base->epoch;

my @tests = (
   {
      expr => '0 0 * * * ? *',
      desc => 'hourly',
      prev => $base_epoch - 3600,  # 17:00
      prev_n => [ $base_epoch - 3*3600, -2*3600, -3600 ],
   },
   {
      expr => '0 0 0 * * ? *',
      desc => 'daily',
      prev => $base_epoch - 86400,
      prev_n => [ $base_epoch - 3*86400, -2*86400, -86400 ],
   },
   {
      expr => '0 0 0 L * ? *',
      desc => 'last day',
      prev => $base->minus_months(1)->with_day_of_month(
         $base->minus_months(1)->length_of_month
      )->epoch,
   },
);

plan tests => scalar(@tests) * 3;

for my $t (@tests) {
   my $cron = Cron::Toolkit->new(expression => $t->{expr});

   subtest $t->{desc} => sub {
      my $prev = $cron->previous($base_epoch);
      is($prev, $t->{prev}, "previous()");

      my $prev_n = $cron->previous_n($base_epoch, 3);
      is_deeply($prev_n, $t->{prev_n}, "previous_n(3)")
         if $t->{prev_n};

      my $n = $cron->previous_n($base_epoch, 1);
      is($n->[0], $prev, "previous_n(1) == previous()");
   };
}


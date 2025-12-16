#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';
use Cron::Toolkit;
use Time::Moment;
use JSON::MaybeXS;
use feature 'say';

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------
srand( time ^ $$ );

my @common_tzs = qw(
  America/New_York
  Europe/London
  Asia/Tokyo
  Australia/Sydney
  America/Los_Angeles
  Europe/Paris
);

my @common_offsets = qw(-300 0 60 540 -480 120);

my $BASE = Time::Moment->new( year => 2025, month => 10, day => 23 );

my @raw_exprs = (

    # ===================================================================
    # 1. CORE PATTERN COVERAGE — Every field × every pattern type
    # ===================================================================

    # Wildcard in one field, others fixed
    '* * * * * * *',           # every second (full wildcard)
    '5 * * * * * *',           # specific second
    '0 5 * * * * *',           # specific minute
    '0 0 5 * * * *',           # specific hour
    '0 0 0 5 * * *',           # specific day-of-month
    '0 0 0 1 5 * *',           # specific month
    '0 0 0 ? * 5 *',           # specific day-of-week
    '0 0 0 * * * 2025',        # specific year

    # Step patterns (*/n) in every field
    '* * * * 2/5 * *',
    '*/15 * * * * * *',
    '0 */5 * * * * *',
    '0 0 */3 * * * *',
    '0 0 0 */7 * * *',
    '0 0 0 1 */2 * *',
    '0 0 0 ? * */2 *',
    '0 0 0 * * * */5',

    # Ranges (-) in every field
    '0-30 * * * * * *',
    '0 10-50 * * * * *',
    '0 0 9-17 * * * *',
    '0 0 0 10-20 * * *',
    '0 0 0 1 3-6 * *',
    '0 0 0 ? * 1-5 *',
    '0 0 0 * * * 2025-2027',

    # Lists (,) in every field
    '0,15,30,45 * * * * * *',
    '0 0,15,30,45 * * * * *',
    '0 0 9,12,15,18 * * * *',
    '0 0 0 1,15 * * *',
    '0 0 0 1 1,6 * *',
    '0 0 0 ? * 1,3,5 *',
    '0 0 0 * * * 2025,2027,2030',

    # ===================================================================
    # 2. SPECIAL DOM / DOW PATTERNS — Full coverage
    # ===================================================================

    # DOM specials
    '0 0 0 L * ? *',           # last day of month
    '0 0 0 L-3 * ? *',
    '0 0 0 LW * ? *',          # last weekday
    '0 0 0 15W * ? *',
    '0 0 0 1W * ? *',
    '0 0 0 31W * ? *',

    # DOW specials
    '0 0 12 ? * 6L *',         # last Saturday
    '0 0 12 ? * SATL *',
    '0 0 12 ? * 1L *',         # last Monday
    '0 0 12 ? * 3#2 *',        # 2nd Wednesday
    '0 0 12 ? * 5#5 *',        # 5th Friday (sometimes skips)
    '0 0 12 ? * 1#1 *',        # 1st Monday
    '0 0 12 ? * MON#1 *',

    # Wrapped ranges
    '0 0 12 ? * 6-2 *',        # Sat→Tue
    '0 0 12 ? * 5-1 *',        # Fri→Mon
    '0 0 12 ? * 7-3 *',        # Sun→Wed

    # ===================================================================
    # 3. REAL-WORLD + BUSINESS LOGIC
    # ===================================================================

    '0 10-50/10 9-17 * * 1-5 *',     # business hours, every 10 mins
    '0 0 9,12,15 * * MON-FRI *',     # 9am, noon, 3pm weekdays
    '0 30 8-17/2 ? * 1-5 *',         # every 2h 8:30–17:30 weekdays
    '0 0 9 ? * MON-FRI *',           # 9 AM weekdays
    '0 0 12 ? * 5-1 *',              # noon on weekends
    '0 0 0 ? * 1#1,L *',             # 1st Monday AND last day
    '0 3 4 2 3-7 ? 2028',

    # Aliases
    '@daily',
    '@hourly',
    '@weekly',
    '@monthly',
    '@yearly',

    # ===================================================================
    # 4. LEAP YEAR EDGE CASES
    # ===================================================================

    '0 0 0 29 2 ? *',                # Feb 29 — leap years only
    '0 0 0 29 FEB ? *',
    '0 0 0 29 2 ? 2024',             # runs
    '0 0 0 29 2 ? 2025',             # no run
    '0 0 0 29 2 ? 2028',             # runs
    '0 0 0 29 2 ? 2000',             # runs (div by 400)
    '0 0 0 29 2 ? 1900',             # no run (div by 100 not 400)
    '0 0 0 L 2 ? *',                 # last day of February
    '0 0 0 L 2 ? 2024',              # → Feb 29
    '0 0 0 L 2 ? 2025',              # → Feb 28

    # ===================================================================
    # 5. DST TRANSITIONS — 100% REAL DATES (2025–2028)
    # ===================================================================

    # Europe/London — Spring forward (last Sun Mar)
    '0 30 1 30 3 ? 2025',            # 01:30 → exists
    '0 30 2 30 3 ? 2025',            # 02:30 → SKIPPED
    '0 30 3 30 3 ? 2025',            # 03:30 → exists

    # Europe/London — Fall back (last Sun Oct)
    '0 30 1 26 10 ? 2025',           # 01:30 → runs twice

    # America/New_York — Spring forward (2nd Sun Mar)
    '0 0 2 9 3 ? 2025',              # 02:00 → SKIPPED
    '0 30 2 8 3 ? 2026',             # 02:30 → SKIPPED

    # America/New_York — Fall back (1st Sun Nov)
    '0 0 1 2 11 ? 2025',             # 01:00 → runs twice
    '0 30 1 1 11 ? 2026',            # 01:30 → runs twice

    # Australia/Sydney — Fall back (1st Sun Apr)
    '0 0 3 6 4 ? 2025',              # 03:00 → SKIPPED

    # Australia/Sydney — Spring forward (1st Sun Oct)
    '0 0 2 5 10 ? 2025',             # 02:00 → SKIPPED

    # Control: no DST
    '0 0 2 9 3 ? 2025',              # Asia/Tokyo — always exists

    # ===================================================================
    # 6. DOW-ONLY "nth weekday" — No DOM cheats
    # ===================================================================

    '0 0 2 ? * 0#2 *',               # 2 AM on 2nd Sunday
    '0 30 2 ? * SUN#2 2025',         # 02:30 on 2nd Sunday → SKIPPED in spring
    '0 0 1 ? * 0#1 2025',            # 01:00 on 1st Sunday → runs twice in fall
    '0 0 12 ? * 6L *',               # noon last Saturday
    '0 0 9 ? * 1#5 *',               # 9 AM on 5th Monday (sometimes skips)
    '0 0 9 ? * MON#1 *',             # first Monday
    '0 0 15 ? * FRI#3 *',            # third Friday
    '0 0 17 ? * LW *',               # last weekday

    # ===================================================================
    # 7. INVALID / EDGE CASES
    # ===================================================================

    '70 * * * * * *',
    '0 99 * * * * *',
    '0 0 25 * * * *',
    '0 0 0 32 * * *',
    '0 0 0 1 13 * *',
    '0 0 0 ? * 8 *',
    '0 0 0 * * * 1899',
    '0 0 0 * * * 2101',
    '0 0 0 ? * 1#6 *',
    '0 0 0 ? * 0 *',
    '0 0 0 * * 2 ?',
    '0 0 0 ? * ? *',
);

# ----------------------------------------------------------------------
# Generate test data
# ----------------------------------------------------------------------
my @data;

for my $expr (@raw_exprs) {
   my ( $tz, $offset_min ) = ( undef, 0 );
   my $rand = rand();

   if ( $rand > 0.25 ) {
      if ( $rand < 0.75 ) {
         $tz = $common_tzs[ int rand @common_tzs ];
      }
      else {
         $offset_min = $common_offsets[ int rand @common_offsets ];
      }
   }

   eval {
      print STDERR "DEBUG: Processing '$expr'\n" if $ENV{DEBUG};

      my $cron = Cron::Toolkit->new( expression => $expr );

      my $as_string        = $cron->as_string;
      my $as_unix_string   = $cron->as_unix_string;
      my $as_quartz_string = $cron->as_quartz_string;
      my $desc             = $cron->describe;

      $cron->time_zone($tz)          if $tz;
      $cron->utc_offset($offset_min) if $offset_min && !$tz;

      my $actual_offset = $cron->utc_offset // 0;
      my $base_epoch    = $BASE->epoch;

      my $is_match   = $cron->is_match($base_epoch);
      my $next_epoch = $cron->next($base_epoch);
      my $prev_epoch = $cron->previous($base_epoch);

      push @data,
        {
         category         => "general",
         expr             => $expr,
         as_string        => $as_string,
         as_unix_string   => $as_unix_string,
         as_quartz_string => $as_quartz_string,
         type             => ( $expr =~ /^@/ ) ? "alias" : ( ( split /\s+/, $expr ) == 5 && $expr !~ /\?/ ) ? "unix" : "quartz",
         tz               => $tz,
         utc_offset       => $actual_offset,
         invalid          => 0,
         desc             => $desc,
         base_epoch       => $base_epoch,
         next_epoch       => $next_epoch,
         prev_epoch       => $prev_epoch,
        };
   } or do {
      my $err = $@;
      $err =~ s/\s+at\s+.*$//s;
      print STDERR "DEBUG: Error for '$expr': $err\n" if $ENV{DEBUG};

      push @data,
        {
         category     => "parsing",
         expr         => $expr,
         invalid      => 1,
         expect_error => $err
        };
   };
}

# ----------------------------------------------------------------------
# Output JSON
# ----------------------------------------------------------------------
my $json = JSON::MaybeXS->new( utf8 => 1, pretty => 1, canonical => 1 );
say $json->encode( \@data );

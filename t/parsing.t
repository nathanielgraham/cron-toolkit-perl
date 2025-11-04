#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Cron::Toolkit;

# Helper – safe access to raw_fields
sub _norm {
   my ( $desc, $expr, $expected, $expected_error ) = @_;
   my $cron;
   eval { $cron = Cron::Toolkit->new( expression => $expr ); };
   if ($expected_error) {
      like( $@, $expected_error, "$desc: error" );
   } else {
      my $raw = $cron->{raw_fields} // [];
      diag "Raw fields      : [" . join( ', ', @$raw ) . "]";
      diag "Normalized fields: [" . join( ', ', @{ $cron->{fields} } ) . "]";
      diag "Optimized expr   : " . $cron->as_string;
      is( $cron->as_string, $expected, $desc );
   }
}

# ----------------------------------------------------------------------
# Unix normalization – DOW 7 and SUN become 0 in AST → as_string shows 0
# ----------------------------------------------------------------------
_norm(
   'Unix DOW 0: normalized',
   '30 14 * * 0',
   '0 30 14 ? * 0 *'
);

_norm(
   'Unix DOW 7: normalized',
   '30 14 * * 7',
   '0 30 14 ? * 0 *'   # 7 → 0 in AST
);

_norm(
   'Unix DOW SUN: normalized',
   '30 14 * * SUN',
   '0 30 14 ? * 0 *'   # SUN → 7 → 0
);

_norm(
   'Unix DOW 1,3,5: normalized',
   '* * * * 1,3,5',
   '0 * * ? * 1,3,5 *'
);

_norm(
   'Unix DOW 1,2,3: normalized',
   '* * * * 1,2,3,4',
   '0 * * ? * 1-4 *'
);

# ----------------------------------------------------------------------
# Quartz normalization
# ----------------------------------------------------------------------
_norm(
   'Quartz DOW 1: normalized to 0',
   '0 0 0 ? * 1 *',
   '0 0 0 ? * 0 *'
);

_norm(
   'Quartz DOW 1#2: unchanged',
   '0 0 0 ? * 1#2 *',
   '0 0 0 ? * 1#2 *'
);

# ----------------------------------------------------------------------
# Invalid inputs – match actual error messages
# ----------------------------------------------------------------------
_norm(
   'Quartz rejects DOW 0',
   '0 0 0 ? * 0 *',
   undef,
   qr/Invalid dow value: 0, must be \[1-7\] in Quartz/
);

_norm(
   'Rejects ? in year',
   '0 0 0 * * ? ?',
   undef,
   qr/Invalid characters in year: \?/
);

_norm(
   'Rejects invalid DOW range',
   '* * * * 5-1',
   undef,
   qr/dow range start 5 must be <= end 1/
);

_norm(
   'Rejects invalid month FOO',
   '30 14 * FOO *',
   undef,
   qr/Invalid characters/
);

_norm(
   'Rejects invalid list element',
   '* * * * 1,99',
   undef,
   qr/dow 99 out of range \[0-7\]/
);

done_testing;

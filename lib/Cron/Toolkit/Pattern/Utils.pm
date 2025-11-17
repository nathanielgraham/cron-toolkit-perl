package Time::Moment::Cron::Utils;
use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(
  %MONTH_MAP %DOW_MAP %MONTH_NAMES %LIMITS %ALIASES %ALLOWED_CHARS format_time num_to_ordinal join_parts 
);

our %EXPORT_TAGS = ( all => [@EXPORT_OK] );

our %MONTH_MAP   = (
   JAN       => 1,
   JANUARY   => 1,
   FEB       => 2,
   FEBRUARY  => 2,
   MAR       => 3,
   MARCH     => 3,
   APR       => 4,
   APRIL     => 4,
   MAY       => 5,
   JUN       => 6,
   JUNE      => 6,
   JUL       => 7,
   JULY      => 7,
   AUG       => 8,
   AUGUST    => 8,
   SEP       => 9,
   SEPTEMBER => 9,
   OCT       => 10,
   OCTOBER   => 10,
   NOV       => 11,
   NOVEMBER  => 11,
   DEC       => 12,
   DECEMBER  => 12
);
our %DOW_MAP = (
   SUN       => 1,
   SUNDAY    => 1,
   MON       => 2,
   MONDAY    => 2,
   TUE       => 3,
   TUESDAY   => 3,
   WED       => 4,
   WEDNESDAY => 4,
   THU       => 5,
   THURSDAY  => 5,
   FRI       => 6,
   FRIDAY    => 6,
   SAT       => 7,
   SATURDAY  => 7
);

our %MONTH_NAMES = (
   1  => 'January',
   2  => 'February',
   3  => 'March',
   4  => 'April',
   5  => 'May',
   6  => 'June',
   7  => 'July',
   8  => 'August',
   9  => 'September',
   10 => 'October',
   11 => 'November',
   12 => 'December'
);

our @fields = qw(second minute hour dom month dow year);
our %day_names   = ( 0 => 'Sunday', 1 => 'Monday', 2 => 'Tuesday', 3 => 'Wednesday', 4 => 'Thursday', 5 => 'Friday', 6 => 'Saturday' );
our %nth_names   = ( 1 => 'first',  2 => 'second', 3 => 'third',   4 => 'fourth',    5 => 'fifth' );
our %field_names = ( 0 => 'second', 1 => 'minute', 2 => 'hour',    3 => 'dom',       4 => 'month', 5 => 'dow', 6 => 'year' );

our %unit_labels = (
   second => [ 'second',          'seconds' ],
   minute => [ 'minute',          'minutes' ],
   hour   => [ 'hour',            'hours' ],
   dom    => [ 'day',             'days' ],
   month  => [ 'month',           'months' ],
   dow    => [ 'day of the week', 'days of the week' ],
   year   => [ 'year',            'years' ]
);

# Exported constants — UPPERCASE
our %LIMITS = (
    second => [0, 59],
    minute => [0, 59],
    hour   => [0, 23],
    dom    => [1, 31],
    month  => [1, 12],
    dow    => [1, 7],
    year   => [1970, 2099],
);

our @FIELDS = qw(second minute hour dom month dow year);

our %limits = (
   second => [ 0,    59 ],
   minute => [ 0,    59 ],
   hour   => [ 0,    23 ],
   dom    => [ 1,    31 ],
   month  => [ 1,    12 ],
   dow    => [ 0,    7 ],
   year   => [ 1970, 2099 ]
);

our %ALLOWED_CHARS = (
   second => qr/^[0-9,\*\/\-]+$/,
   minute => qr/^[0-9,\*\/\-]+$/,
   hour   => qr/^[0-9,\*\/\-]+$/,
   dom    => qr/^[0-9,\*\/\-?LW#]+$/,
   dow    => qr/^[0-9,\*\/\-?L#]+$/,
   month  => qr/^[0-9,\*\/\-]+$/,
   year   => qr/^[0-9,\*\/\-]+$/
);

our %allowed_types = (
   second => [qw(single range step list wildcard)],
   minute => [qw(single range step list wildcard)],
   hour   => [qw(single range step list wildcard)],
   dom    => [qw(single range step list wildcard unspecified last lastW nearest_weekday)],
   month  => [qw(single range step list wildcard)],
   dow    => [qw(single range step list wildcard unspecified nth last)],
   year   => [qw(single range step list wildcard)]
);

our %ALIASES = (
   '@yearly'   => '0 0 0 1 1 ? *',
   '@annually' => '0 0 0 1 1 ? *',
   '@monthly'  => '0 0 0 L ? * *',
   '@weekly'   => '0 0 0 ? * ? *',
   '@daily'    => '0 0 0 * * ? *',
   '@midnight' => '0 0 0 * * ? *',
   '@hourly'   => '0 0 * * * ? *',
);

our %ordinal_suffix = ( 1    => 'st',  21    => 'st', 31 => 'st', 2 => 'nd', 22 => 'nd', 3 => 'rd', 23 => 'rd', map { $_ => 'th' } grep { !/1[123]$/ } 4 .. 30 );
our %joiners        = ( list => 'and', range => 'through' );
our %templates      = (
   every_N_second          => 'every {step} seconds',
   every_N_minute          => 'every {step} minutes',
   every_N_hour            => 'every {step} hours',
   dom_single_every        => 'on the {ordinal} of every month',
   dom_range_every         => 'the {start} through {end} of every month',
   dom_list                => '{list} of every month',
   dom_last                => 'on the last day of every month',
   dom_lw                  => 'on the last weekday of every month',
   dow_single              => 'every {day}',
   dow_range               => 'every {start} through {end}',
   dow_list                => '{list}',
   dow_nth                 => 'on the {nth} {day} of every month',
   month_range             => 'from {start} to {end}',
   year_in                 => 'every day in {year}',
   year_range              => 'every day from {start} to {end}',
   dom_last_offset         => 'on the {ordinal} last day of every month',
   dom_nearest_weekday     => 'on the nearest weekday to the {ordinal} of every month',
   step_range              => 'every {step} minutes from {start} to {end} past {hour}',
   step_single             => 'every {step} hours starting at {start}',
   dom_special_month_range => 'the {dom_desc} of {month_range}',
   dow_nth_month_range     => 'on the {nth} {day} of {month_range}',
   dom_single_year_single  => 'on the {ordinal} of every month in {year}',
   dom_list_year_range     => 'on the {list} of every month {year_range}',
   dow_range_year_range    => 'every {start} through {end} {year_range}',
   dow_list_year_range     => 'every {list} {year_range}',
   dom_step_month_range    => 'every {step} days starting on the {start} {month_range}',
   dow_single_month_range  => 'every {day} {month_range}',
   dow_range_month_range   => 'every {start} through {end} {month_range}',
   dom_single_month_single => 'on the {ordinal} of every month in {month}',
   dow_single_year         => 'every {day} in {year}',

   #dom_single_month_single => 'on the {ordinal} in {month}',
   month_year_single       => 'in {month} of {year}',
   dom_single_month_single => 'on the {ordinal} of {month}',                  # Restored "of" for natural flow
   dom_single_year_single  => 'on the {ordinal} of every month in {year}',    # Fallback for no month
);

sub plural_unit {
   my ( $unit, $count ) = @_;
   return $count == 1 ? $unit : $unit . 's';
}


sub num_to_ordinal {
    my $n = shift;
    #return '' unless defined $n;
    #return 'first'  if $n == 1;
    #return 'second' if $n == 2;
    #return 'third'  if $n == 3;
    return "$n" . (
        $n % 10 == 1 && $n != 11 ? 'st' :
        $n % 10 == 2 && $n != 12 ? 'nd' :
        $n % 10 == 3 && $n != 13 ? 'rd' : 'th'
    );
}

sub join_parts {
   my @p = grep { defined && length } @_;
   return @p == 0 ? '' : @p == 1 ? $p[0] : @p == 2 ? "$p[0] $joiners{list} $p[1]" : join( ', ', @p[ 0 .. $#p - 1 ] ) . " $joiners{list} $p[-1]";
}

sub format_time {
    my ($sec, $min, $hour) = @_;
    return "midnight" if $hour == 0 && $min == 0 && $sec == 0;
    my $ampm = $hour >= 12 ? 'PM' : 'AM';
    $hour = $hour % 12 || 12;
    return sprintf("%d:%02d:%02d %s", $hour, $min, $sec, $ampm);
}

sub is_midnight { my ( $h, $m, $s ) = @_; return $h == 0 && $m == 0 && $s == 0; }
sub time_suffix { my $h = shift; return $h == 0 ? 'midnight' : $h == 12 ? 'noon' : ''; }
sub field_unit  { my ( $f, $c ) = @_; $c //= 1; my ( $s, $p ) = @{ $unit_labels{$f} }; return $c == 1 ? $s : $p; }
sub quartz_dow  { my ($iso_dow) = @_; return $iso_dow == 7 ? 1 : $iso_dow + 1; }

sub ordinal_list {
   join( ', ', map { num_to_ordinal($_) } @_ );
}
sub step_ordinal { my $n = shift; return $n . ( $n == 1 ? 'st' : $n == 2 ? 'nd' : $n == 3 ? 'rd' : 'th' ); }
sub complex_join { join( ', ', @_ ) . ' at {time}'; }

1;

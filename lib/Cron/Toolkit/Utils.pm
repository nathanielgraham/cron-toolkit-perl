package Cron::Toolkit::Utils;
use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(
  format_time num_to_ordinal field_unit join_parts fill_template is_midnight time_suffix quartz_dow
  quartz_dow_normalize unix_dow_normalize %aliases %field_names %allowed_chars %allowed_types
  ordinal_list step_ordinal complex_join normalize generate_list_desc %limits %DOW_MAP_UNIX @FIELDS %LIMITS
  %MONTH_MAP %DOW_MAP_QUARTZ %MONTH_NAMES %DAY_NAMES %ALLOWED_CHARS %ALIASES %nth_names %unit_labels %ordinal_suffix %joiners %templates
);

our %EXPORT_TAGS = ( all => [@EXPORT_OK] );
our %MONTH_MAP = (
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

our %DOW_MAP_QUARTZ = (
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

our %DOW_MAP_UNIX = (
   SUN       => 7,
   SUNDAY    => 7,
   MON       => 1,
   MONDAY    => 1,
   TUE       => 2,
   TUESDAY   => 2,
   WED       => 3,
   WEDNESDAY => 3,
   THU       => 4,
   THURSDAY  => 4,
   FRI       => 5,
   FRIDAY    => 5,
   SAT       => 6,
   SATURDAY  => 6
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

our %DAY_NAMES   = ( 0 => 'Sunday', 1 => 'Monday', 2 => 'Tuesday', 3 => 'Wednesday', 4 => 'Thursday', 5 => 'Friday', 6 => 'Saturday' );
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
    dow    => [0, 7],
    year   => [1970, 2099],
);

our @FIELDS = qw(second minute hour dom month dow year);

our %ALLOWED_CHARS = (
   second => qr/^[0-9,\*\/\-]+$/,
   minute => qr/^[0-9,\*\/\-]+$/,
   hour   => qr/^[0-9,\*\/\-]+$/,
   dom    => qr/^[0-9,\*\/\-?LW#]+$/,
   dow    => qr/^[0-9,\*\/\-?L#]+$/,
   month  => qr/^[0-9,\*\/\-]+$/,
   year   => qr/^[0-9,\*\/\-]+$/
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

sub num_to_ordinal {
    my $n = shift;
    return $n . (
        $n % 10 == 1 && $n != 11 ? 'st' :
        $n % 10 == 2 && $n != 12 ? 'nd' :
        $n % 10 == 3 && $n != 13 ? 'rd' : 'th'
    );
}

sub format_time {
    my ($sec, $min, $hour) = @_;
    return "midnight" if $hour == 0 && $min == 0 && $sec == 0;
    my $ampm = $hour >= 12 ? 'PM' : 'AM';
    $hour = $hour % 12 || 12;
    return   $min && $sec ? sprintf("%d:%02d:%02d %s", $hour, $min, $sec, $ampm) 
           : $min ? sprintf("%d:%02d %s", $hour, $min, $ampm)
           : "$hour $ampm";

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

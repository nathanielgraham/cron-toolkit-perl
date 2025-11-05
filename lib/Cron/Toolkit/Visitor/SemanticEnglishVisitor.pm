package Cron::Toolkit::Visitor::SemanticEnglishVisitor;
use strict;
use warnings;
use parent 'Cron::Toolkit::Visitor';

use Cron::Toolkit::Utils qw(
  num_to_ordinal %month_names %day_names join_parts
);

# ----------------------------------------------------------------------
# Constructor
# ----------------------------------------------------------------------
sub new {
   my $class = shift;
   my $self  = $class->SUPER::new(@_);
   $self->{model} = { time => {}, date => {} };
   return $self;
}

# ----------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------
sub visit {
   my ( $self, $node, @results ) = @_;
   return $self->_render if $node->{type} eq 'root';

   my $field = $node->{field_type} or return;
   my $m     = $self->{model};

   if ( $field =~ /^(second|minute|hour)$/ ) {
      $self->_populate_time( $node, $field );
   }
   else {
      $self->_populate_date( $node, $field );
   }
   return;
}

# ----------------------------------------------------------------------
# Populate time fields
# ----------------------------------------------------------------------
sub _populate_time {
   my ( $self, $node, $field ) = @_;
   my $m    = $self->{model}{time};
   my $type = $node->{type};

   if ( $type eq 'single' ) {
      $m->{$field} = { kind => 'value', value => $node->{value} };
   }
   elsif ( $type eq 'wildcard' ) {
      $m->{$field} = { kind => 'every' };
   }
   elsif ( $type eq 'range' ) {
      my ( $s, $e ) = map { $_->{value} } @{ $node->{children} };
      $m->{$field} = { kind => 'range', start => $s, end => $e };
   }
   elsif ( $type eq 'list' ) {
      my @items = map { $self->_render_field( $_, $field ) } @{ $node->{children} };
      $m->{$field} = { kind => 'list', items => \@items };
   }
   elsif ( $type eq 'step' ) {
      my $base = $self->_render_field( $node->{children}[0], $field );
      my $step = $node->{children}[1]{value};
      $m->{$field} = { kind => 'step', base => $base, step => $step };
   }
}

# ----------------------------------------------------------------------
# Populate date fields
# ----------------------------------------------------------------------
sub _populate_date {
   my ( $self, $node, $field ) = @_;
   my $m = $self->{model}{date};

   return if $node->{type} eq 'unspecified';

   my $type = $node->{type};

   if ( $type eq 'single' ) {
      $m->{$field} = { kind => 'value', value => $node->{value} };
   }
   elsif ( $type eq 'wildcard' ) {
      $m->{$field} = { kind => 'every' };
   }
   elsif ( $type eq 'range' ) {
      my ( $s, $e ) = map { $_->{value} } @{ $node->{children} };
      $m->{$field} = { kind => 'range', start => $s, end => $e };
   }
   elsif ( $type eq 'list' ) {
      my @items = map { $self->_render_field( $_, $field ) } @{ $node->{children} };
      $m->{$field} = { kind => 'list', items => \@items };
   }
   elsif ( $type eq 'step' ) {
      my $base = $self->_render_field( $node->{children}[0], $field );
      my $step = $node->{children}[1]{value};
      $m->{$field} = { kind => 'step', base => $base, step => $step };
   }
   elsif ( $type eq 'last' ) {
      my $offset = ( $node->{value} =~ /L-(\d+)/ ) ? $1 : 0;
      $m->{dom} = { kind => 'last', offset => $offset };
   }
   elsif ( $type eq 'lastW' ) {
      $m->{dom} = { kind => 'lastW' };
   }
   elsif ( $type eq 'nearest_weekday' ) {
      my ($d) = $node->{value} =~ /(\d+)W/;
      $m->{dom} = { kind => 'nearest_weekday', day => $d };
   }
   elsif ( $type eq 'nth' ) {
      my ( $dow, $nth ) = $node->{value} =~ /(\d+)#(\d+)/;
      $m->{dow} = { kind => 'nth', dow => $dow, nth => $nth };
   }
}

# ----------------------------------------------------------------------
# Helper: render field value
# ----------------------------------------------------------------------
sub _render_field {
   my ( $self, $node, $field ) = @_;
   return unless $node;

   my $type = $node->{type};

   if ( $type eq 'single' ) {
      return { kind => 'value', value => $node->{value} };
   }
   elsif ( $type eq 'wildcard' ) {
      return { kind => 'every' };
   }
   elsif ( $type eq 'range' ) {
      my ( $s, $e ) = map { $_->{value} } @{ $node->{children} };
      return { kind => 'range', start => $s, end => $e };
   }
   elsif ( $type eq 'list' ) {
      my @items = map { $self->_render_field( $_, $field ) } @{ $node->{children} };
      return { kind => 'list', items => \@items };
   }
   elsif ( $type eq 'step' ) {
      my $base = $self->_render_field( $node->{children}[0], $field );
      my $step = $node->{children}[1]{value};
      return { kind => 'step', base => $base, step => $step };
   }
   return;
}

# ----------------------------------------------------------------------
# Render full description
# ----------------------------------------------------------------------
sub _render {
   my $self = shift;
   my $m    = $self->{model};

   my $time = $self->_render_time( $m->{time} );
   my $date = $self->_render_date( $m->{date} );

   return $self->_combine( $time, $date );
}

# ----------------------------------------------------------------------
# Custom format_time — NO IMPORT
# ----------------------------------------------------------------------
sub _format_time {
   my ( $self, $sec, $min, $hour ) = @_;
   return "midnight" if $hour == 0 && $min == 0 && $sec == 0;
   my $ampm = $hour >= 12 ? 'PM' : 'AM';
   $hour = $hour % 12 || 12;
   return sprintf( "%d:%02d:%02d %s", $hour, $min, $sec, $ampm );
}

# ----------------------------------------------------------------------
# _render_time — FINAL
# ----------------------------------------------------------------------
sub _render_time {
   my ( $self, $t ) = @_;
   my $s = $t->{second} // { kind => 'every' };
   my $m = $t->{minute} // { kind => 'every' };
   my $h = $t->{hour}   // { kind => 'every' };

   my @parts;

   # 1. All fixed
   if ( $s->{kind} eq 'value' && $m->{kind} eq 'value' && $h->{kind} eq 'value' ) {
      my $time = $self->_format_time( $s->{value}, $m->{value}, $h->{value} );
      return $time eq 'midnight' ? "midnight every day" : "$time every day";
   }

   # 2. Unified rendering
   my @fields = (
      { data => $s, unit => 'second', plural => 'seconds', type => 'sec' },
      { data => $m, unit => 'minute', plural => 'minutes', type => 'min' },
      { data => $h, unit => 'hour',   plural => 'hours',   type => 'hour' },
   );

   for my $i ( 0 .. 2 ) {
      my $f    = $fields[$i];
      my $next = $i < 2 ? $fields[ $i + 1 ] : undef;

      my $part = $self->_render_field_part( $f->{data}, $f );
      next unless $part;

      if ( $next && $next->{data}{kind} eq 'every' ) {
         $part .= " after every $next->{unit}";
      }

      push @parts, $part;
   }

   return join( ', ', @parts ) || 'every hour';
}

# ----------------------------------------------------------------------
# Unified field renderer — FINAL
# ----------------------------------------------------------------------
sub _render_field_part {
   my ( $self, $field, $info ) = @_;
   my $kind = $field->{kind};

   if ( $kind eq 'value' ) {
      my $val = $field->{value};
      return '' if $val == 0;
      my $unit   = $info->{unit}   || 'unit';
      my $plural = $info->{plural} || 'units';
      return "$val " . ( $val == 1 ? $unit : $plural );
   }

   if ( $kind eq 'range' ) {
      my $from = $self->_format_scalar( $field->{start}, $info->{type} );
      my $to   = $self->_format_scalar( $field->{end},   $info->{type} );
      return "every $info->{unit} from $from to $to";
   }

   if ( $kind eq 'step' ) {
      my $base_str = '';
      my $end_str  = '';
      if ( $field->{base}{kind} eq 'range' ) {
         my $from = $self->_format_scalar( $field->{base}{start}, $info->{type} );
         my $to   = $self->_format_scalar( $field->{base}{end},   $info->{type} );
         $base_str = " from $from";
         $end_str  = " to $to";
      }
      elsif ( $field->{base}{kind} eq 'value' ) {
         my $val = $self->_format_scalar( $field->{base}{value}, $info->{type} );
         $base_str = " starting at $val";
      }
      return "every $field->{step} $info->{unit}" . ( $field->{step} > 1 ? 's' : '' ) . $base_str . $end_str;
   }

   if ( $kind eq 'list' ) {
      my @items = map { $self->_render_field_part( $_, $info ) } @{ $field->{items} };
      return join_parts(@items);
   }

   if ( $kind eq 'nth' ) {
      my $ordinal = num_to_ordinal( $field->{nth} );
      my $day     = $day_names{ $field->{dow} } || $field->{dow};
      return "on the $ordinal $day of every month";
   }

   if ( $kind eq 'last' ) {
      return "on the last day of every month" if !$field->{offset};
      return "on the " . num_to_ordinal( $field->{offset} ) . " to last day of every month";
   }

   if ( $kind eq 'lastW' ) {
      return "on the last weekday of every month";
   }

   if ( $kind eq 'nearest_weekday' ) {
      return "on the nearest weekday to the " . num_to_ordinal( $field->{day} ) . " of every month";
   }

   return '';
}

# ----------------------------------------------------------------------
# Format scalar — FINAL
# ----------------------------------------------------------------------
sub _format_scalar {
   my ( $self, $val, $type ) = @_;
   return $val                              if $type eq 'sec';
   return sprintf( ":%02d", $val )          if $type eq 'min';
   return $self->_format_time( 0, 0, $val ) if $type eq 'hour';
   return $month_names{$val} || $val        if $type eq 'month';
   return num_to_ordinal($val)              if $type eq 'dom';
   return $day_names{$val} || $val          if $type eq 'dow';
   return $val;
}

# ----------------------------------------------------------------------
# _render_date — FINAL
# ----------------------------------------------------------------------
sub _render_date {
   my ( $self, $d ) = @_;
   my @parts;

   # In _render_date
   my @fields = (
      { data => $d->{dom},   unit => 'day',   plural => 'days',   type => 'dom' },
      { data => $d->{dow},   unit => 'day',   plural => 'days',   type => 'dow' },
      { data => $d->{month}, unit => 'month', plural => 'months', type => 'month' },
      { data => $d->{year},  unit => 'year',  plural => 'years',  type => 'year' },
   );

   for my $f (@fields) {
      next unless $f->{data};
      my $part = $self->_render_field_part( $f->{data}, $f );
      next unless $part;
      push @parts, $part;
   }

   return join( ', ', @parts ) || 'every day';
}

# ----------------------------------------------------------------------
# _combine
# ----------------------------------------------------------------------
sub _combine {
   my ( $self, $time, $date ) = @_;
   return $time if !$date || $date eq 'every day';
   return "$time, $date";
}

1;

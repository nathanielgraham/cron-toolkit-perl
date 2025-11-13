package Cron::Toolkit::Visitor::SemanticEnglishVisitor;
use strict;
use warnings;
use parent 'Cron::Toolkit::Visitor';
use Data::Dumper;

use Cron::Toolkit::Utils qw(:all);
#  num_to_ordinal %month_names %day_names join_parts
#);

# ----------------------------------------------------------------------
# Constructor
# ----------------------------------------------------------------------
sub new {
   my $class = shift;
   my $self  = $class->SUPER::new(@_);
   return $self;
}

# ----------------------------------------------------------------------
# Entry point
# ----------------------------------------------------------------------
sub visit {
   my ( $self, $node, @results ) = @_;

   #print Dumper($node);
   #return $self->_parse_node($node) if $node->{type} eq 'root';
   #print "$node->{field_type} = " . $self->_parse_node($node) . " \n";
   print " -- " . $self->_parse_node($node). " ";
   #print Dumper($node);
   return 'hello';
}

sub visit2 {
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
# Custom format_time
# ----------------------------------------------------------------------
sub _format_time {
   my ( $self, $sec, $min, $hour ) = @_;
   return "midnight" if $hour == 0 && $min == 0 && $sec == 0;
   my $ampm = $hour >= 12 ? 'PM' : 'AM';
   $hour = $hour % 12 || 12;
   if ( $sec == 0 ) {
      return sprintf( "%d:%02d %s", $hour, $min, $ampm );
   }
   else {
      return sprintf( "%d:%02d:%02d %s", $hour, $min, $sec, $ampm );
   }
}

# ----------------------------------------------------------------------
# _render_time
# ----------------------------------------------------------------------
sub _render_time {
   my ( $self, $t ) = @_;

   #print Dumper($t);
   my $s = $t->{second} // { kind => 'every' };
   my $m = $t->{minute} // { kind => 'every' };
   my $h = $t->{hour}   // { kind => 'every' };

   my @parts;

   # 1. All fixed
   if ( $s->{kind} eq 'value' && $m->{kind} eq 'value' && $h->{kind} eq 'value' ) {
      my $time = $self->_format_time( $s->{value}, $m->{value}, $h->{value} );

      #return $time eq 'midnight' ? "midnight every day" : "$time every day";
      return $time;
   }

   # 2. Unified rendering
   my @fields = (
      { data => $s, unit => 'second', plural => 'seconds', type => 'sec' },
      { data => $m, unit => 'minute', plural => 'minutes', type => 'min' },
      { data => $h, unit => 'hour',   plural => 'hours',   type => 'hour' },
   );

   #print Dumper(\@fields);

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

sub _parse_node {
   my ( $self, $node ) = @_;
   my $type = $node->{type};
   #print Dumper($node);
   #my $unit = $node->{field_type} =~ /^dom|dow$/ ? 'day' : $node->{field_type};
   if ( $type eq 'single' ) {
      return $node->value;
   }
   elsif ( $type eq 'wildcard' ) {
      return "every";
   }

   elsif ( $type eq 'range' ) {
      my ( $from, $to ) = map { $_->value } @{ $node->{children} };
      return "from $from to $to";
   }
   elsif ( $node->type eq 'step' ) {
      my $string;
      my ( $base, $step ) = @{ $node->children };

      my $unit = $node->field =~ /^dom|dow$/ ? 'day' : $node->field;
      my $limit = $LIMITS{ $node->field }->[1];
      my $from = $base->type eq 'range' ? $self->_parse_node($base) 
               : "from $base->{value} to $limit";
      $step = num_to_ordinal( $step->value );

      return "every $step $unit $base";
   }
   elsif ( $node->type eq 'list' ) {
      my @list;
      push (@list, $self->_parse_node($_)) for @{ $node->children };
      print Dumper(\@list);
      return join_parts(@list);
   }
   elsif ( $node->type eq 'nth' ) {
      my $ordinal = num_to_ordinal( $node->value );
      return "on the $ordinal day of every month";
   }

   elsif ( $node->type eq 'last' ) {
      return "on the last day of every month";
      #return "on the " . num_to_ordinal( $field->{offset} ) . " to last day of every month";
   }

   elsif ( $node->type eq 'lastW' ) {
      return "on the last weekday of every month";
   }

   elsif ( $node->type eq 'nearest_weekday' ) {
      return "on the nearest weekday to the " . num_to_ordinal( $node->value ) . " of every month";
   }
   #print "NODE: $node->{type}, $node->{field_type}\n";
   #print Dumper($node);
}

# ----------------------------------------------------------------------
# Unified field renderer
# ----------------------------------------------------------------------
sub _render_field_part {
   my ( $self, $field, $info ) = @_;
   my $kind = $field->{kind};

   if ( $kind eq 'value' ) {
      my $v = $field->{value};
      if ( $info->{unit} =~ /^(second|minute|hour)$/ ) {
         return '' if $v == 0;
         my $u = $v == 1 ? $info->{unit} : $info->{plural};
         return "$v $u";
      }
      elsif ( $info->{type} eq 'year' ) {
         return $v;
      }
      else {
         return $self->_format_scalar( $v, $info->{type} );
      }
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
# Format scalar
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
# _render_date
# ----------------------------------------------------------------------
sub _render_date {
   my ( $self, $d ) = @_;
   my @parts;

   print Dumper($d);

   # In _render_date
   my @fields = (
      { data => $d->{dom},   unit => 'day',   plural => 'days',   type => 'dom' },
      { data => $d->{dow},   unit => 'day',   plural => 'days',   type => 'dow' },
      { data => $d->{month}, unit => 'month', plural => 'months', type => 'month' },
      { data => $d->{year},  unit => 'year',  plural => 'years',  type => 'year' },
   );

   #print Dumper(\@fields);
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

   #return $time if !$date || $date eq 'every day';
   #return "$time, $date";
   return "TIME: $time -- DATE:  $date";
}

1;

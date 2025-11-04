package Cron::Toolkit::Matcher;
use strict;
use warnings;
use Time::Moment;
use Cron::Toolkit::Utils qw(%LIMITS @FIELDS);
use List::Util           qw(min max);
use Data::Dumper;

sub new {
   my ( $class, %args ) = @_;
   return bless {%args}, $class;
}

# ===================================================================
# MAIN API: next() and previous()
# ===================================================================

sub previous {
   my ( $self, $epoch_seconds ) = @_;
   $epoch_seconds //= time;

   my $clamped = max( $epoch_seconds, $self->{begin_epoch} );

   return undef if $clamped < $self->{begin_epoch};

   my $tm = Time::Moment->from_epoch($clamped)->with_offset_same_instant( $self->{utc_offset} );
   $tm = $tm->minus_seconds(1);

   # H:M:S shortcut 
   foreach my $i ( 0 .. 2 ) {
      my $node = $self->{tree}{children}[$i];

      my $lowval  = $self->_lowest_allowed( $tm, $node );
      my $highval = $self->_highest_allowed( $tm, $node );
      my $tm_high = $self->_set_date( $tm, $node, $highval );
      my $tm_low  = $self->_set_date( $tm, $node, $lowval );

      if ( $tm->is_before($tm_low) ) {
         $tm = $self->_set_date( $tm, $node, $highval );
         $tm = $self->_minus_one( $tm, $self->{tree}{children}[ $i + 1 ] );
      }
      elsif ( $tm->is_after($tm_high) ) {
         $tm = $self->_set_date( $tm, $node, $highval );
      }

      my $current_val = $self->_field_value( $tm, $node->{field_type} );
      for (my $c = $current_val; $c >= $lowval; $c--) {
         my $c_tm    = $self->_set_date( $tm, $node, $c );
         my $visitor = Cron::Toolkit::Visitor::MatchVisitor->new( value => $c, tm => $c_tm );
         if ( $node->traverse($visitor) ) {
            $tm = $c_tm;
            last;
         }
      }
   }

   my $min_tm = Time::Moment->new(
      year   => 1970,
      month  => 1,
      day    => 1,
      hour   => 1,
      minute => 1,
      second => 1,
   );

   my $min_iter = $min_tm->delta_days($tm);
   for my $day ( 0 .. $min_iter ) {
      return $tm->epoch if $self->_match($tm);
      $tm = $tm->minus_days(1);
   }
}

sub next {
   my ( $self, $epoch_seconds ) = @_;
   $epoch_seconds //= time;

   my $clamped = max( $epoch_seconds, $self->{begin_epoch} );

   return undef if $clamped > $self->{end_epoch};

   my $tm = Time::Moment->from_epoch($clamped)->with_offset_same_instant( $self->{utc_offset} );
   $tm = $tm->plus_seconds(1);

   # H:M:S shortcut
   foreach my $i ( 0 .. 2 ) {
      my $node = $self->{tree}{children}[$i];

      my $lowval  = $self->_lowest_allowed( $tm, $node );
      my $highval = $self->_highest_allowed( $tm, $node );
      my $tm_high = $self->_set_date( $tm, $node, $highval );
      my $tm_low  = $self->_set_date( $tm, $node, $lowval );

      if ( $tm->is_before($tm_low) ) {
         $tm = $self->_set_date( $tm, $node, $lowval );
      }
      elsif ( $tm->is_after($tm_high) ) {
         $tm = $self->_set_date( $tm, $node, $lowval );
         $tm = $self->_plus_one( $tm, $self->{tree}{children}[ $i + 1 ] );
      }

      for my $c ( $self->_field_value( $tm, $node->{field_type} ) .. $highval ) {
         my $c_tm    = $self->_set_date( $tm, $node, $c );
         my $visitor = Cron::Toolkit::Visitor::MatchVisitor->new( value => $c, tm => $c_tm );
         if ( $node->traverse($visitor) ) {
            $tm = $c_tm;
            last;
         }
      }
   }
   my $max_tm = Time::Moment->new(
      year   => 2099,
      month  => 12,
      day    => 31,
      hour   => 23,
      minute => 59,
      second => 59,
   );

   my $max_iter = $tm->delta_days($max_tm);
   for my $day ( 0 .. $max_iter ) {
      return $tm->epoch if $self->_match($tm);
      $tm = $tm->plus_days(1);
   }
}

sub next_n {
   my ( $self, $epoch_seconds, $n ) = @_;
   $epoch_seconds //= time;
   $n //= 1;
   my $max_iter = 10000;

   die "Invalid epoch_seconds" unless defined $epoch_seconds && $epoch_seconds =~ /^\d+$/ && $epoch_seconds >= 0;
   die "Invalid n" unless $n =~ /^\d+$/ && $n > 0;
   die "Invalid max_iter" unless $max_iter =~ /^\d+$/ && $max_iter >= $n;

   my @results;
   my $current = $epoch_seconds;
   my $iter = 0;

   for ( 1 .. $n ) {
      $iter++;
      die "Exceeded max_iter ($max_iter) in next_n" if $iter > $max_iter;
      my $next = $self->next($current);
      last unless defined $next;
      push @results, $next;
      $current = $next + 1;
   }
   return \@results;
}

sub previous_n {
   my ( $self, $epoch_seconds, $n ) = @_;
   $epoch_seconds //= time;
   $n //= 1;
   my $max_iter = 10000;
   die "Invalid epoch_seconds" unless defined $epoch_seconds && $epoch_seconds =~ /^\d+$/ && $epoch_seconds >= 0;
   die "Invalid n" unless $n =~ /^\d+$/ && $n > 0;
   die "Invalid max_iter" unless $max_iter =~ /^\d+$/ && $max_iter >= $n;

   my @results;
   my $current = $epoch_seconds;
   my $iter = 0;

   while ( @results < $n ) {
      $iter++;
      die "Exceeded max_iter ($max_iter) in previous_n" if $iter > $max_iter;
      my $prev = $self->previous($current);
      last unless defined $prev;
      unshift @results, $prev;  # oldest first
      $current = $prev - 1;
   }
   return \@results;
}

sub match {
   my ( $self, $epoch_seconds ) = @_;
   return 0 unless defined $epoch_seconds;
   my $tm = Time::Moment->from_epoch($epoch_seconds)->with_offset_same_instant( $self->{utc_offset} );
   return $self->_match($tm);
}

sub _set_date {
   my ( $self, $tm, $node, $value ) = @_;
   my $field_type = $node->{field_type};
   return $tm->with_second($value)       if $field_type eq 'second';
   return $tm->with_minute($value)       if $field_type eq 'minute';
   return $tm->with_hour($value)         if $field_type eq 'hour';
   return $tm->with_day_of_month($value) if $field_type eq 'dom';
   return $tm->with_month($value)        if $field_type eq 'month';
   if ( $field_type eq 'dow' ) {
      $value = 7 if $value == 0;
      return $tm->with_day_of_week($value);
   }
   return $tm->with_year($value) if $field_type eq 'year';
}

sub _plus_one {
   my ( $self, $tm, $node ) = @_;
   my $field_type = $node->{field_type};
   return $tm->plus_seconds(1) if $field_type eq 'second';
   return $tm->plus_minutes(1) if $field_type eq 'minute';
   return $tm->plus_hours(1)   if $field_type eq 'hour';
   return $tm->plus_days(1)    if $field_type eq 'dom';
   return $tm->plus_months(1)  if $field_type eq 'month';
   return $tm->plus_weeks(1)   if $field_type eq 'dow';
   return $tm->plus_years(1)   if $field_type eq 'year';
}

sub _minus_one {
   my ( $self, $tm, $node ) = @_;
   my $field_type = $node->{field_type};
   return $tm->minus_seconds(1) if $field_type eq 'second';
   return $tm->minus_minutes(1) if $field_type eq 'minute';
   return $tm->minus_hours(1)   if $field_type eq 'hour';
   return $tm->minus_days(1)    if $field_type eq 'dom';
   return $tm->minus_months(1)  if $field_type eq 'month';
   return $tm->minus_weeks(1)   if $field_type eq 'dow';
   return $tm->minus_years(1)   if $field_type eq 'year';
}

sub _match {
   my ( $self, $tm ) = @_;
   my @nodes = @{ $self->{tree}{children} };
   for my $i ( 0 .. $#FIELDS ) {
      my $node = $nodes[$i] or next;
      next if $node->{type} eq 'wildcard' || $node->{type} eq 'unspecified';
      next if $i == 3 && $nodes[5]{type} ne 'unspecified';
      next if $i == 5 && $nodes[3]{type} ne 'unspecified';
      my $value   = $self->_field_value( $tm, $FIELDS[$i] );
      my $visitor = Cron::Toolkit::Visitor::MatchVisitor->new( value => $value, tm => $tm );
      return 0 unless $node->traverse($visitor);
   }
   return 1;
}

sub _field_value {
   my ( $self, $tm, $type ) = @_;
   return $tm->second       if $type eq 'second';
   return $tm->minute       if $type eq 'minute';
   return $tm->hour         if $type eq 'hour';
   return $tm->day_of_month if $type eq 'dom';
   return $tm->month        if $type eq 'month';
   return $tm->day_of_week  if $type eq 'dow';
   return $tm->year         if $type eq 'year';
}

sub _lowest_allowed {
   my ( $self, $tm, $node ) = @_;

   #my $node  = $self->{tree}{children}[$i];
   my $field = $node->{field_type};
   my ( $min, $max ) = @{ $LIMITS{$field} };
   $max = $tm->length_of_month if $field eq 'dom';

   for my $v ( $min .. $max ) {
      my $test_tm = $tm;
      $test_tm = $test_tm->with_day_of_month($v) if $field eq 'dom';
      my $visitor = Cron::Toolkit::Visitor::MatchVisitor->new( value => $v, tm => $test_tm );
      return $v if $node->traverse($visitor);
   }
   return undef;
}

sub _highest_allowed {
   my ( $self, $tm, $node ) = @_;
   my $field = $node->{field_type};
   my ( $min, $max ) = @{ $LIMITS{$field} };
   $max = $tm->length_of_month if $field eq 'dom';

   for my $v ( reverse $min .. $max ) {
      my $test_tm = $tm;
      $test_tm = $test_tm->with_day_of_month($v) if $field eq 'dom';
      my $visitor = Cron::Toolkit::Visitor::MatchVisitor->new( value => $v, tm => $test_tm );
      return $v if $node->traverse($visitor);
   }
   return undef;
}

1;

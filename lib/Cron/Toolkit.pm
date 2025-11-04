package Cron::Toolkit;

# ABSTRACT: Cron parser, describer, and scheduler with full Quartz support
# VERSION
$VERSION = 0.08;
use strict;
use warnings;
use Time::Moment;
use Cron::Toolkit::Utils qw(:all);
use Cron::Toolkit::Pattern::CompositePattern;
use Cron::Toolkit::Pattern::LeafPattern;
use Cron::Toolkit::Matcher;
use List::Util qw(max min);
use Exporter   qw(import);
use feature 'say';
use Data::Dumper;

=head1 NAME
Cron::Toolkit - Cron parser, describer, and scheduler with full Quartz support
=cut

sub new_from_unix {
   my ( $class, %args ) = @_;
   $args{is_quartz} = 0;
   my $self = $class->_new(%args);
   return $self;
}

sub new_from_quartz {
   my ( $class, %args ) = @_;
   $args{is_quartz} = 1;
   my $self = $class->_new(%args);
   return $self;
}

sub new {
   my ( $class, %args ) = @_;
   die "expression required" unless defined $args{expression};

   my @fields = split /\s+/, $args{expression};
   if ( @fields == 5 ) {
      $args{is_quartz} = 0;
   }
   elsif ( @fields == 6 || @fields == 7 ) {
      $args{is_quartz} = 1;
   }
   else {
      die "expected 5-7 fields";
   }
   my $self = $class->_new(%args);
   return $self;
}

sub _new {
   my ( $class, %args ) = @_;
   die "expression required" unless defined $args{expression};
   my $expr = uc $args{expression};
   $expr =~ s/\s+/ /g;
   $expr =~ s/^\s+|\s+$//g;

   # alias support
   if ( $expr =~ /^(@.*)/ ) {
      my $alias = $1;
      $expr = $aliases{$alias} // $expr;
      print STDERR "DEBUG: Alias '$alias' mapped to '$expr'\n" if $ENV{Cron_DEBUG};
   }

   my @fields     = split /\s+/, $expr;
   my @raw_fields = @fields;

   # normalize to 7-field quartz expression
   if ( $args{is_quartz} ) {
      die "Expected 6-7 fields, got " . scalar(@fields) unless @fields == 6 || @fields == 7;
      push( @fields, '*' ) if @fields == 6;    # year

      # Reject Quartz DOW 0
      if ( $fields[5] =~ /\b0\b/ && $fields[5] !~ /#\d+/ ) {
         die "Invalid dow value: 0, must be [1-7] in Quartz";
      }

      # Map Quartz DOW names
      while ( my ( $name, $num ) = each %dow_map_quartz ) {
         $fields[5] =~ s/\b\Q$name\E\b/$num/gi;
      }

      # Normalize Quartz DOW 1-7 to 0-6, skip nth and step
      $fields[5] =~ s/(?<![#\/])(\b[1-7]\b)(?![#\/])/$1-1/ge;
   }
   else {
      die "Expected 5 fields, got " . scalar(@fields) unless @fields == 5;
      unshift( @fields, 0 );    # seconds
      push( @fields, '*' );     # year

      # convert dow names to unix numerical equivalent
      while ( my ( $name, $num ) = each %dow_map_unix ) {
         $fields[5] =~ s/\b\Q$name\E\b/$num/gi;
      }
   }

   # Convert month names to numerical equivalent
   while ( my ( $name, $num ) = each %month_map ) { $fields[4] =~ s/\b\Q$name\E\b/$num/gi; }

   # enforce dom/dow mutual exclusivity
   if ( $fields[3] ne '?' && $fields[5] eq '*' ) {
      $fields[5] = '?';
   }
   elsif ( $fields[3] eq '*' && $fields[5] ne '?' ) {
      $fields[3] = '?';
   }
   elsif ( $fields[3] ne '?' && $fields[5] ne '?' ) {
      die "dow and dom cannot both be specified\n";
   }
   elsif ( $fields[3] eq '?' && $fields[5] eq '?' ) {
      die "dow and dom cannot both be unspecified\n";
   }

   die "Invalid characters" unless join( ' ', @fields ) =~ /^[#LW\d\?\*\s\-\/,]+$/;

   my $self = bless {
      fields      => \@fields,
      raw_fields  => \@raw_fields,
      utc_offset  => 0,
      time_zone   => 'UTC',
      begin_epoch => time - ( 10 * 365 * 86400 ),    # ~10 years ago
      end_epoch   => time + ( 10 * 365 * 86400 ),    # ~10 years ahead
   }, $class;

   #$self->utc_offset( $args{utc_offset} ) if defined $args{utc_offset};
   #$self->time_zone( $args{time_zone} ) if defined $args{time_zone};
   #$self->begin_epoch( $args{begin} ) if defined $args{begin_epoch};
   #$self->end_epoch( $args{end} ) if defined $args{end_epoch};
   $self->user( $args{user} )       if defined $args{user};
   $self->command( $args{command} ) if defined $args{command};
   $self->env( $args{env} )         if defined $args{env};

   $self->{root} = Cron::Toolkit::Pattern::CompositePattern->new( type => 'root' );

   $self->_build_tree;

   $self->{matcher} = Cron::Toolkit::Matcher->new(
      tree        => $self->{root},
      utc_offset  => $self->utc_offset,
      begin_epoch => $self->begin_epoch,
      end_epoch   => $self->end_epoch,
   );

   return $self;
}

sub _build_tree {
   my $self  = shift;
   my @types = qw(second minute hour dom month dow year);
   for my $i ( 0 .. $#types ) {
      my $node = $self->_build_node( $types[$i], $self->{fields}[$i] );
      #$node = $self->_optimize_node( $node, $types[$i] );
      $self->{root}->add_child($node);
   }
   $self->_finalize_dow_root();
}

sub _optimize_node {
   my ( $self, $node, $field ) = @_;

   print STDERR "DEBUG: Optimizing $field node: type=$node->{type}\n" if $ENV{Cron_DEBUG};

   # Get field limits
   my ( $min, $max ) = @{ $limits{$field} };
   $min = 0 if $field eq 'dow';

   # Step collapse — only if degenerate
   if ( $node->{type} eq 'step' ) {
      my $base_node = $node->{children}[0];
      my $step      = $node->{children}[1]{value};
      my @values;

      if ( $base_node->{type} eq 'wildcard' ) {
         my ( $min, $max ) = @{ $limits{$field} };
         $min    = 0 if $field eq 'dow';
         @values = ( $min .. $max );
      }
      elsif ( $base_node->{type} eq 'single' ) {
         @values = ( $base_node->{value} .. $max );
      }
      elsif ( $base_node->{type} eq 'range' ) {
         my ( $start, $end ) = map { $_->{value} } @{ $base_node->{children} };
         @values = ( $start .. $end );
      }

      my @stepped;
      for ( my $v = $values[0] ; $v <= $values[-1] ; $v += $step ) {
         push @stepped, $v if grep { $_ == $v } @values;
      }

      # === DEGENERATE CASE: 0 or 1 value → collapse ===
      if ( @stepped == 0 ) {
         print STDERR "DEBUG: Step collapse to wildcard: $field\n" if $ENV{Cron_DEBUG};
         return Cron::Toolkit::Pattern::LeafPattern->new(
            type       => 'wildcard',
            value      => '*',
            field_type => $field
         );
      }
      elsif ( @stepped == 1 ) {
         print STDERR "DEBUG: Step collapse to single: $stepped[0] in $field\n" if $ENV{Cron_DEBUG};
         return Cron::Toolkit::Pattern::LeafPattern->new(
            type       => 'single',
            value      => $stepped[0],
            field_type => $field
         );
      }

      # === NON-DEGENERATE: keep as step (but optimize base if possible) ===
      # Recursively optimize base (e.g., 1-10/5 → range(1,10))
      my $optimized_base = $self->_optimize_node( $base_node, $field );
      return $node if $optimized_base == $base_node;    # no change

      my $new_step = Cron::Toolkit::Pattern::CompositePattern->new(
         type       => 'step',
         field_type => $field
      );
      $new_step->add_child($optimized_base);
      $new_step->add_child( $node->{children}[1] );     # step value
      return $new_step;
   }

   # List-to-range
   if ( $node->{type} eq 'list' ) {
      my @values = sort { $a <=> $b } map { $_->{value} }
        grep { $_->{type} eq 'single' } @{ $node->{children} };
      if ( @values >= 2 && $values[-1] - $values[0] == $#values ) {
         print STDERR "DEBUG: List collapse to range: $values[0]-$values[-1] in $field\n" if $ENV{Cron_DEBUG};
         my $range = Cron::Toolkit::Pattern::CompositePattern->new(
            type       => 'range',
            field_type => $field
         );
         $range->add_child(
            Cron::Toolkit::Pattern::LeafPattern->new(
               type       => 'single',
               value      => $values[0],
               field_type => $field
            )
         );
         $range->add_child(
            Cron::Toolkit::Pattern::LeafPattern->new(
               type       => 'single',
               value      => $values[-1],
               field_type => $field
            )
         );
         return $range;
      }
   }

   return $node;
}

sub _finalize_dow_root {
   my $self     = shift;
   my $dow_node = $self->{root}{children}[5];

   print STDERR "DEBUG: Finalizing DOW node: type=$dow_node->{type}\n" if $ENV{Cron_DEBUG};

   if ( $dow_node->{type} eq 'single' && $dow_node->{value} == 7 ) {
      print STDERR "DEBUG: Mapping DOW 7 to 0\n" if $ENV{Cron_DEBUG};
      $dow_node = Cron::Toolkit::Pattern::LeafPattern->new(
         type       => 'single',
         value      => 0,
         field_type => 'dow'
      );
      $self->{root}{children}[5] = $dow_node;
   }
   elsif ( $dow_node->{type} eq 'range' ) {
      my ( $start_node, $end_node ) = @{ $dow_node->{children} };
      if ( $start_node->{value} == 7 || $end_node->{value} == 7 ) {
         print STDERR "DEBUG: Mapping DOW range with 7 to 0\n" if $ENV{Cron_DEBUG};
         my $new_start = $start_node->{value} == 7 ? 0 : $start_node->{value};
         my $new_end   = $end_node->{value} == 7   ? 0 : $end_node->{value};
         my $range     = Cron::Toolkit::Pattern::CompositePattern->new(
            type       => 'range',
            field_type => 'dow'
         );
         $range->add_child(
            Cron::Toolkit::Pattern::LeafPattern->new(
               type       => 'single',
               value      => $new_start,
               field_type => 'dow'
            )
         );
         $range->add_child(
            Cron::Toolkit::Pattern::LeafPattern->new(
               type       => 'single',
               value      => $new_end,
               field_type => 'dow'
            )
         );
         $self->{root}{children}[5] = $range;
      }
   }
   elsif ( $dow_node->{type} eq 'list' ) {
      my @new_children;
      for my $child ( @{ $dow_node->{children} } ) {
         if ( $child->{type} eq 'single' && $child->{value} == 7 ) {
            print STDERR "DEBUG: Mapping DOW list element 7 to 0\n" if $ENV{Cron_DEBUG};
            push @new_children,
              Cron::Toolkit::Pattern::LeafPattern->new(
               type       => 'single',
               value      => 0,
               field_type => 'dow'
              );
         }
         else {
            push @new_children, $child;
         }
      }
      if ( @new_children != @{ $dow_node->{children} } ) {
         my $list = Cron::Toolkit::Pattern::CompositePattern->new(
            type       => 'list',
            field_type => 'dow'
         );
         $list->add_child($_) for @new_children;
         $self->{root}{children}[5] = $list;
      }
   }
}

sub _build_node {
   my ( $self, $field, $value ) = @_;

   print STDERR "DEBUG: Parsing $field: '$value'\n" if $ENV{Cron_DEBUG};

   # Validate characters using Utils.pm
   die "Invalid characters in $field: $value" unless $value =~ $allowed_chars{$field};

   # Get field limits, adjust DOW to [0-7]
   my ( $min, $max ) = @{ $limits{$field} };
   $min = 0 if $field eq 'dow';

   my $node;

   # Combined validation and node creation
   if ( $value eq '*' ) {
      die "Invalid type wildcard for $field: not in allowed types"
        unless grep { $_ eq 'wildcard' } @{ $allowed_types{$field} };
      $node = Cron::Toolkit::Pattern::LeafPattern->new(
         type       => 'wildcard',
         value      => '*',
         field_type => $field
      );
   }
   elsif ( $value eq '?' ) {
      die "Syntax: ? only allowed in dom or dow, not $field"
        unless $field =~ /^(dom|dow)$/;
      die "Invalid type unspecified for $field: not in allowed types"
        unless grep { $_ eq 'unspecified' } @{ $allowed_types{$field} };
      $node = Cron::Toolkit::Pattern::LeafPattern->new(
         type       => 'unspecified',
         value      => '?',
         field_type => $field
      );
   }
   elsif ( $value =~ /^L(-\d+)?$/ ) {
      die "Syntax: L only allowed in dom or dow, not $field"
        unless $field =~ /^(dom|dow)$/;
      die "Invalid type last for $field: not in allowed types"
        unless grep { $_ eq 'last' } @{ $allowed_types{$field} };
      if ($1) {
         my $offset = $1 =~ /-(\d+)/ ? $1 : 0;
         die "$field offset $offset too large" if ( $field eq 'dom' && $offset > 30 ) || ( $field eq 'dow' && $offset > 6 );
      }
      $node = Cron::Toolkit::Pattern::LeafPattern->new(
         type       => 'last',
         value      => $value,
         field_type => $field
      );
   }
   elsif ( $value =~ /^LW$/ ) {
      die "Syntax: LW only allowed in dom, not $field" unless $field eq 'dom';
      die "Invalid type lastW for $field: not in allowed types"
        unless grep { $_ eq 'lastW' } @{ $allowed_types{$field} };
      $node = Cron::Toolkit::Pattern::LeafPattern->new(
         type       => 'lastW',
         value      => 'LW',
         field_type => $field
      );
   }
   elsif ( $value =~ /^(\d+)W$/ ) {
      die "Syntax: W only allowed in dom, not $field" unless $field eq 'dom';
      die "Invalid type nearest_weekday for $field: not in allowed types"
        unless grep { $_ eq 'nearest_weekday' } @{ $allowed_types{$field} };
      my $day = $1;
      die "dom $day out of range [1-31]" unless $day >= 1 && $day <= 31;
      $node = Cron::Toolkit::Pattern::LeafPattern->new(
         type       => 'nearest_weekday',
         value      => $value,
         field_type => $field
      );
   }
   elsif ( $value =~ /^(\d+)#(\d+)$/ ) {
      die "Syntax: # only allowed in dow, not $field" unless $field eq 'dow';
      die "Invalid type nth for $field: not in allowed types"
        unless grep { $_ eq 'nth' } @{ $allowed_types{$field} };
      my ( $day, $nth ) = ( $1, $2 );
      die "dow $day out of range [1-7]" unless $day >= 1 && $day <= 7;    # Pre-normalization for nth
      die "nth $nth out of range [1-5]" unless $nth >= 1 && $nth <= 5;
      $node = Cron::Toolkit::Pattern::LeafPattern->new(
         type       => 'nth',
         value      => $value,
         field_type => $field
      );
   }
   elsif ( $value =~ /^\d+$/ ) {
      die "Invalid type single for $field: not in allowed types"
        unless grep { $_ eq 'single' } @{ $allowed_types{$field} };
      die "$field $value out of range [$min-$max]" unless $value >= $min && $value <= $max;
      $node = Cron::Toolkit::Pattern::LeafPattern->new(
         type       => 'single',
         value      => $value,
         field_type => $field
      );
   }
   elsif ( $value =~ /^(\d+)-(\d+)$/ ) {
      die "Invalid type range for $field: not in allowed types"
        unless grep { $_ eq 'range' } @{ $allowed_types{$field} };
      my ( $start, $end ) = ( $1, $2 );
      die "$field start $start out of range [$min-$max]" unless $start >= $min && $start <= $max;
      die "$field end $end out of range [$min-$max]"     unless $end >= $min   && $end <= $max;
      die "$field range start $start must be <= end $end" if $start > $end;
      $node = Cron::Toolkit::Pattern::CompositePattern->new(
         type       => 'range',
         field_type => $field
      );
      $node->add_child(
         Cron::Toolkit::Pattern::LeafPattern->new(
            type       => 'single',
            value      => $start,
            field_type => $field
         )
      );
      $node->add_child(
         Cron::Toolkit::Pattern::LeafPattern->new(
            type       => 'single',
            value      => $end,
            field_type => $field
         )
      );
   }
   elsif ( $value =~ /^(\*|\d+)\/(\d+)$/ ) {
      die "Invalid type step for $field: not in allowed types"
        unless grep { $_ eq 'step' } @{ $allowed_types{$field} };
      my ( $base_str, $step ) = ( $1, $2 );
      die "$field step $step out of range [$min-$max]" unless $step >= $min && $step <= $max;
      die "$field base $base_str out of range [$min-$max]" if $base_str ne '*' && ( $base_str < $min || $base_str > $max );
      print STDERR "DEBUG: Parsing step: base=$base_str, step=$step\n" if $ENV{Cron_DEBUG};
      $node = Cron::Toolkit::Pattern::CompositePattern->new(
         type       => 'step',
         field_type => $field
      );
      my $base_node =
        $base_str eq '*'
        ? Cron::Toolkit::Pattern::LeafPattern->new( type => 'wildcard', value => '*',       field_type => $field )
        : Cron::Toolkit::Pattern::LeafPattern->new( type => 'single',   value => $base_str, field_type => $field );
      $node->add_child($base_node);
      $node->add_child(
         Cron::Toolkit::Pattern::LeafPattern->new(
            type       => 'step_value',
            value      => $step,
            field_type => $field
         )
      );
   }
   elsif ( $value =~ /^(\*|\d+)-(\d+)\/(\d+)$/ ) {
      die "Invalid type step for $field: not in allowed types"
        unless grep { $_ eq 'step' } @{ $allowed_types{$field} };
      my ( $start, $end, $step ) = ( $1, $2, $3 );
      die "$field range start $start out of range [$min-$max]" if $start ne '*' && ( $start < $min || $start > $max );
      die "$field range end $end out of range [$min-$max]" unless $end >= $min  && $end <= $max;
      die "$field step $step out of range [$min-$max]"     unless $step >= $min && $step <= $max;
      die "$field range start $start must be <= end $end" if $start ne '*' && $start > $end;
      print STDERR "DEBUG: Parsing step range: start=$start, end=$end, step=$step\n" if $ENV{Cron_DEBUG};
      my $range = Cron::Toolkit::Pattern::CompositePattern->new(
         type       => 'range',
         field_type => $field
      );
      $range->add_child(
         Cron::Toolkit::Pattern::LeafPattern->new(
            type       => 'single',
            value      => $start,
            field_type => $field
         )
      );
      $range->add_child(
         Cron::Toolkit::Pattern::LeafPattern->new(
            type       => 'single',
            value      => $end,
            field_type => $field
         )
      );
      $node = Cron::Toolkit::Pattern::CompositePattern->new(
         type       => 'step',
         field_type => $field
      );
      $node->add_child($range);
      $node->add_child(
         Cron::Toolkit::Pattern::LeafPattern->new(
            type       => 'step_value',
            value      => $step,
            field_type => $field
         )
      );
   }
   elsif ( $value =~ /,/ ) {
      die "Invalid type list for $field: not in allowed types"
        unless grep { $_ eq 'list' } @{ $allowed_types{$field} };
      $node = Cron::Toolkit::Pattern::CompositePattern->new(
         type       => 'list',
         field_type => $field
      );
      print STDERR "DEBUG: Parsing list: elements=[" . join( ',', split /,/, $value ) . "]\n" if $ENV{Cron_DEBUG};
      for my $sub ( split /,/, $value ) {
         print STDERR "DEBUG: Parsing list element: $sub in $field\n" if $ENV{Cron_DEBUG};
         eval {
            my $sub_node = $self->_build_node( $field, $sub );
            die "Invalid list element in $field: list not allowed" if $sub_node->{type} eq 'list';
            $node->add_child($sub_node);
         };
         if ($@) {
            my $error = $@;
            $error =~ s/^Invalid $field:/Invalid $field list element:/;
            $error =~ s/^$field ([^:]+):/Invalid $field list element $1:/;
            die $error;
         }
      }
   }
   else {
      die "Unsupported field: $value ($field)";
   }

   return $node;
}

sub utc_offset {
   my ( $self, $new_offset ) = @_;
   if ( @_ > 1 ) {
      if ( !defined $new_offset || $new_offset !~ /^-?\d+$/ || $new_offset < -1080 || $new_offset > 1080 ) {
         die "Invalid utc_offset '$new_offset': must be an integer between -1080 and 1080 minutes";
      }
      $self->{utc_offset} = $new_offset;
      print STDERR "DEBUG: utc_offset: set to $new_offset\n" if $ENV{Cron_DEBUG};
   }
   print STDERR "DEBUG: utc_offset: returning $self->{utc_offset}\n" if $ENV{Cron_DEBUG};
   return $self->{utc_offset};
}

sub time_zone {
   my ( $self, $new_tz ) = @_;
   if ( @_ > 1 ) {
      require DateTime::TimeZone;
      my $tz   = $new_tz;
      my $zone = eval { DateTime::TimeZone->new( name => $tz ); } or do {
         die "Invalid time_zone '$tz': must be a valid TZ identifier ($@)";
      };
      $self->{time_zone} = $tz;
      my $tm = Time::Moment->now_utc;
      $self->{utc_offset} = $zone->offset_for_datetime($tm) / 60;    # Recalc to minutes (DST-aware)
      print STDERR "DEBUG: time_zone: set to $tz (offset: $self->{utc_offset})\n" if $ENV{Cron_DEBUG};
   }
   print STDERR "DEBUG: time_zone: returning $self->{time_zone}\n" if $ENV{Cron_DEBUG};
   return $self->{time_zone};
}

sub begin_epoch {
   my ( $self, $new_begin ) = @_;
   if ( @_ > 1 ) {
      die "Invalid begin_epoch '$new_begin': must be a non-negative integer" unless defined $new_begin && $new_begin =~ /^\d+$/ && $new_begin >= 0;
      $self->{begin_epoch} = $new_begin;
   }
   return $self->{begin_epoch};
}

sub end_epoch {
   my ( $self, $new_end ) = @_;
   if ( @_ > 1 ) {
      die "Invalid end_epoch '$new_end': must be undef or a non-negative integer" unless !defined $new_end || ( $new_end =~ /^\d+$/ && $new_end >= 0 );
      $self->{end_epoch} = $new_end;
   }
   return $self->{end_epoch};
}

sub user {
   my ($self) = @_;
   return $self->{user};
}

sub command {
   my ($self) = @_;
   return $self->{command};
}

sub env {
   my ($self) = @_;
   return $self->{env};
}

sub describe {
   my ($self) = @_;
   my $visitor = Cron::Toolkit::Visitor::EnglishVisitor->new();
   return $self->{root}->traverse($visitor);
}

sub is_match {
   my ( $self, $epoch_seconds ) = @_;
   return $self->{matcher}->match($epoch_seconds);
}

# Symmetric next() with auto-clamp defaults
sub next {
   my ( $self, $epoch_seconds ) = @_;
   $epoch_seconds //= time;
   die "Invalid epoch_seconds: must be a non-negative integer" unless defined $epoch_seconds && $epoch_seconds =~ /^\d+$/ && $epoch_seconds >= 0;

   # Delegate to matcher (handles clamping, search, bounds)
   #return $self->{matcher}->find_next_or_previous($epoch_seconds, 1);
   return $self->{matcher}->next($epoch_seconds);
}

# Symmetric previous() with auto-clamp defaults
sub previous {
   my ( $self, $epoch_seconds ) = @_;
   $epoch_seconds //= time;
   die "Invalid epoch_seconds: must be a non-negative integer" unless defined $epoch_seconds && $epoch_seconds =~ /^\d+$/ && $epoch_seconds >= 0;

   # Delegate to matcher (handles clamping, search, bounds)
   #return $self->{matcher}->find_next_or_previous($epoch_seconds, -1);
   return $self->{matcher}->previous($epoch_seconds);
}

# next_n with max_iter guard
use constant MAX_ITER => 10000;    # Configurable? Later.

sub next_n {
   my ( $self, $epoch_seconds, $n, $max_iter ) = @_;
   $epoch_seconds //= time;
   $n             //= 1;
   $max_iter      //= MAX_ITER;
   die "Invalid epoch_seconds: must be a non-negative integer" unless defined $epoch_seconds && $epoch_seconds =~ /^\d+$/ && $epoch_seconds >= 0;
   die "Invalid n: must be positive integer"                   unless defined $n             && $n             =~ /^\d+$/ && $n > 0;
   die "Invalid max_iter: must be positive integer >= n"       unless defined $max_iter      && $max_iter      =~ /^\d+$/ && $max_iter >= $n;
   my @results;
   my $current = $epoch_seconds;
   my $iter    = 0;

   for ( 1 .. $n ) {
      $iter++;
      die "Exceeded max_iter ($max_iter) in next_n; possible infinite loop? Tighten end_epoch or reduce n." if $iter > $max_iter;
      my $next = $self->next($current);
      last unless defined $next;
      push @results, $next;
      $current = $next + 1;    # Skip self-match
   }
   return \@results;
}

# previous_n with max_iter guard
sub previous_n {
   my ( $self, $epoch_seconds, $n, $max_iter ) = @_;
   $epoch_seconds //= time;
   $n             //= 1;
   $max_iter      //= MAX_ITER;
   die "Invalid epoch_seconds: must be a non-negative integer" unless defined $epoch_seconds && $epoch_seconds =~ /^\d+$/ && $epoch_seconds >= 0;
   die "Invalid n: must be positive integer"                   unless defined $n             && $n             =~ /^\d+$/ && $n > 0;
   die "Invalid max_iter: must be positive integer >= n"       unless defined $max_iter      && $max_iter      =~ /^\d+$/ && $max_iter >= $n;
   my @results;
   my $current = $epoch_seconds;
   my $iter    = 0;

   while ( @results < $n ) {
      $iter++;
      die "Exceeded max_iter ($max_iter) in previous_n; possible infinite loop? Tighten begin_epoch or reduce n." if $iter > $max_iter;
      my $prev = $self->previous($current);
      last unless defined $prev;
      unshift @results, $prev;    # Oldest first (ascending)
      $current = $prev - 1;       # Advance backward
   }
   return \@results;
}

sub next_occurrences {
   my $self = shift;
   return $self->next_n(@_);
}

sub as_unix_string {
   my $self = shift;
   my $expr = $self->_as_string;
   $expr =~ s/\?/*/;
   my @fields = split( /\s+/, $expr );
   shift @fields;    # remove seconds
   pop @fields;      # remove year
   return join( ' ', @fields );
}

sub as_quartz_string {
   my $self   = shift;
   my $expr   = $self->_as_string;
   my @fields = split /\s+/, $expr;

   # Increment standalone DOW numbers: 0-6 → 1-7
   # But NOT if preceded by /, #, - or followed by W
   $fields[5] =~ s{
        (?<![\\/#\-])   # not after /, #, -
        \b([0-6])\b     # standalone 0–6
        (?![W])         # not before W
    }{
        $1 + 1
    }gex;

   return join ' ', @fields;
}

sub as_string {
   my $self = shift;
   return $self->_as_string;
}

sub _as_string {
   my $self = shift;
   return $self->_rebuild_from_node( $self->{root} );
}

sub to_json {
   my $self = shift;
   return JSON::PP::encode_json(
      {
         expression  => $self->_as_string,
         description => $self->describe,
         utc_offset  => $self->utc_offset,
         time_zone   => $self->time_zone,
         begin_epoch => $self->begin_epoch,
         end_epoch   => $self->end_epoch,
      }
   );
}

# new_from_crontab class method
sub new_from_crontab {
   my ( $class, $content ) = @_;
   die "crontab content required (string)" unless defined $content && length $content;
   my @crons;
   my %env;
   foreach my $line ( split /\n/, $content ) {

      # Strip trailing comments and trim
      $line             =~ s/\s*#.*$//;       # Remove comments from end
      $line             =~ s/^\s+|\s+$//g;    # Trim whitespace
      next unless $line =~ /\S/;              # Skip empty
                                              # Env var: KEY=VALUE (simple; no quotes handled yet)
      if ( $line =~ /^([A-Z_][A-Z0-9_]*)=(.*)$/ ) {
         $env{$1} = $2;
         next;
      }

      # Split into tokens (simple space split; preserves quoted if manual, but for robustness, assume no embedded quotes in fields)
      my @parts = split /\s+/, $line;

      # Iterative token consumption for cron prefix
      my @cron_parts;
      my $is_alias = 0;
      for my $part (@parts) {
         last if @cron_parts >= 7;    # Cap at max Quartz fields
         if ( @cron_parts == 0 && $part =~ /^@/ ) {

            # Alias as single token
            push @cron_parts, $part;
            $is_alias = 1;
            last;                     # Aliases are single
         }
         elsif ( $part =~ /^[0-9*?,\/\-L#W?]+$/ ) {    # Cron-like: digits, *, ?, -, /, ,, L, W, #
            push @cron_parts, $part;
         }
         else {
            last;                                      # Non-cron token
         }
      }

      # Validate expression length
      my $expr = join ' ', @cron_parts;
      next unless $is_alias || ( @cron_parts >= 5 && @cron_parts <= 7 );

      # Extract user: Next token after prefix, if simple word (alphanumeric, no / or special)
      my ( $user, $command ) = ( undef, undef );
      my $cron_end   = @cron_parts;
      my $next_start = $cron_end;
      if ( @parts > $cron_end ) {
         my $potential_user = $parts[$cron_end];
         if ( $potential_user =~ /^\w+$/ ) {    # Simple username: letters/digits/_
            $user       = $potential_user;
            $next_start = $cron_end + 1;
         }
      }

      # Command: Remainder (join from next_start, preserving original spacing if needed; here simple join)
      $command = join ' ', @parts[ $next_start .. $#parts ] if @parts > $next_start;

      # Create object (new() auto-handles Unix/Quartz/aliases)
      eval {
         my $cron = $class->new(
            expression => $expr,
            user       => $user,
            command    => $command,
            env        => {%env}      # Copy current env
         );
         push @crons, $cron;
      };
      warn "Skipped invalid crontab line: '$line' ($@)" if $@;
   }
   return @crons;
}

# --------------------------------------------------------------
#  NEW dump_tree – pretty, field-labelled, correct tree graphics
# --------------------------------------------------------------

# ------------------------------------------------------------------
# dump_tree – pretty-print the AST
# ------------------------------------------------------------------
sub dump_tree {
    my ( $self, $node, $prefix, $is_last, $field_idx ) = @_;
    $node      //= $self->{root};
    $prefix    //= '';
    $is_last   //= 1;               # root is the only top-level node
    $field_idx //= -1;              # -1 = root

    # ----- field label (once per top-level field) -----------------
    my @field_names = qw(second minute hour dom month dow year);
    my $label = '';
    if ( $field_idx >= 0 && $field_idx < @field_names ) {
        $label = $field_names[$field_idx] . ' ';
    }

    # ----- node description ---------------------------------------
    my $type  = $node->{type}  // 'root';
    my $value = $node->{value} // '';
    my $desc  = ucfirst($type);
    $desc .= " ($value)" if $value ne '';

    # ----- connector ------------------------------------------------
    my $connector = $field_idx < 0 ? '' : ( $is_last ? '└─ ' : '├─ ' );
    say $prefix . $connector . $label . $desc;

    # ----- recurse into children -----------------------------------
    my $children = $node->{children} // [];
    return unless @$children;

    my $new_prefix = $prefix . ( $is_last ? '   ' : '│  ' );
    for my $i ( 0 .. $#$children ) {
        my $child      = $children->[$i];
        my $child_last = ( $i == $#$children );
        # Pass the *same* field index to all children of a field node
        my $child_idx  = ( $field_idx >= 0 ) ? $field_idx : $i;
        $self->dump_tree( $child, $new_prefix, $child_last, $child_idx );
    }
}

sub _rebuild_from_node {
   my ( $self, $node ) = @_;
   my $type = $node->{type};
   return '*'            if $type eq 'wildcard';
   return '?'            if $type eq 'unspecified';
   return $node->{value} if $type eq 'single' || $type eq 'last' || $type eq 'lastW' || $type eq 'nth' || $type eq 'nearest_weekday' || $type eq 'step_value';
   return $self->_rebuild_from_node( $node->{children}[0] ) . '-' . $self->_rebuild_from_node( $node->{children}[1] ) if $type eq 'range';
   return $self->_rebuild_from_node( $node->{children}[0] ) . '/' . $self->_rebuild_from_node( $node->{children}[1] ) if $type eq 'step';
   return join ',', map { $self->_rebuild_from_node($_) } @{ $node->{children} } if $type eq 'list';
   return join ' ', map { $self->_rebuild_from_node($_) } @{ $node->{children} } if $type eq 'root';
   die "Unsupported for rebuild: $type";
}

1;
__END__

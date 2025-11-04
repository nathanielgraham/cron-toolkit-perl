package Cron::Toolkit::Visitor::EnglishVisitor;
use strict;
use warnings;
use parent 'Cron::Toolkit::Visitor';
use Cron::Toolkit::Utils qw(
   num_to_ordinal format_time %month_names %day_names
   join_parts field_unit
);

sub new {
   my ($class, %args) = @_;
   my $self = $class->SUPER::new(%args);
   $self->{field_order} = [qw(second minute hour dom month dow year)];
   return $self;
}

sub visit {
   my ($self, $node, @child_results) = @_;
   my $type = $node->{type} // '';
   return $self->_fuse($node) if $type eq 'root';
   return $node;
}

sub _fuse {
   my ($self, $root) = @_;
   my @fields = @{ $root->{children} };

   my @time_data;
   my @date_data;

   for my $i (0..6) {
      my $field = $self->{field_order}[$i];
      my $node = $fields[$i];
      my $data = $self->_render_data($node, $field);
      next unless $data;

      if ($i <= 2) { push @time_data, $data; }
      else         { push @date_data, $data; }
   }

   my $time = $self->_join_time(@time_data);
   my $date = $self->_join_date(@date_data);

   # Add "every day" if no date context
   if ($time && !$date && $time !~ /every|on|in/) {
      $time .= " every day";
   }

   return $time if $time && !$date;
   return $date if $date && !$time;
   return "$time, $date" if $time && $date;
   return "every second";
}

# ————————————————————
# RENDER: DATA-ONLY
# ————————————————————

sub _render_data {
   my ($self, $node, $field) = @_;
   return undef unless $node;

   my $type = $node->{type};

   if ($type eq 'single') {
      my $v = $node->{value};
      return undef if $v == 0 && $field =~ /^(second|minute|hour)$/;

      return { field => $field, value => $v, kind => 'value' };
   }

   if ($type eq 'wildcard') {
      return { field => $field, value => "every $field", kind => 'context' } if $field =~ /^(minute|hour)$/;
      return undef;
   }

   if ($type eq 'range') {
      my ($s, $e) = map { $_->{value} } @{$node->{children}};
      return { field => $field, value => [$s, $e], kind => 'range' };
   }

   if ($type eq 'list') {
      my @values = map { $_->{value} } @{$node->{children}};
      return { field => $field, value => \@values, kind => 'list' };
   }

   if ($type eq 'step') {
      my $base = $node->{children}[0];
      my $step = $node->{children}[1]{value};
      return { field => $field, base => $base, step => $step, kind => 'step' };
   }

   if ($type eq 'last') {
      my $offset = $node->{value} =~ /L-(\d+)/ ? $1 : 0;
      return { field => 'dom', value => $offset, kind => 'last' };
   }
   if ($type eq 'lastW') { return { field => 'dom', kind => 'lastW' }; }
   if ($type eq 'nearest_weekday') {
      my ($d) = $node->{value} =~ /(\d+)W/;
      return { field => 'dom', value => $d, kind => 'nearest_weekday' };
   }
   if ($type eq 'nth') {
      my ($dow, $nth) = $node->{value} =~ /(\d+)#(\d+)/;
      return { field => 'dow', dow => $dow, nth => $nth, kind => 'nth' };
   }

   return undef;
}

# ————————————————————
# JOIN: TIME — DATA-DRIVEN
# ————————————————————

sub _join_time {
   my ($self, @data) = @_;
   return "" unless @data;

   my ($sec, $min, $hour) = (0, 0, 0);
   my @context;
   my @values;

   for my $d (@data) {
      if ($d->{kind} eq 'value') {
         if ($d->{field} eq 'second') { $sec = $d->{value}; }
         elsif ($d->{field} eq 'minute') { $min = $d->{value}; }
         elsif ($d->{field} eq 'hour') { $hour = $d->{value}; }
         else { push @values, $d; }
      } elsif ($d->{kind} eq 'context') {
         push @context, $d->{value};
      } else {
         push @values, $d;
      }
   }

   my $time = "";
   if ($sec || $min || $hour) {
      $time = format_time($sec, $min, $hour, { omit_seconds_if_zero => 1 });
   }

   my $has_every_minute = grep { /every minute/ } @context;
   my $has_every_hour   = grep { /every hour/ } @context;

   my $result = "";

   if ($has_every_minute) {
      $result .= "every minute";
   } elsif ($has_every_hour) {
      $result .= "every hour";
   }

   if ($time) {
      if ($has_every_minute && $has_every_hour) {
         $result .= " after every hour";
      } elsif ($has_every_minute) {
         $result .= " at $time";
      } else {
         $result .= " $time";
      }
   }

   for my $d (@values) {
      my $str = $self->_render_value($d);
      $result .= " $str" if $str;
   }

   return $result;
}

# ————————————————————
# JOIN: DATE — DATA-DRIVEN
# ————————————————————

sub _join_date {
   my ($self, @data) = @_;
   return "" unless @data;

   my @final;

   for my $d (@data) {
      my $str = $self->_render_value($d);
      push @final, $str if $str;
   }

   return join " ", @final;
}

# ————————————————————
# RENDER: VALUE FROM DATA
# ————————————————————

sub _render_value {
   my ($self, $d) = @_;

   if ($d->{kind} eq 'value') {
      return "" if $d->{value} == 0;
      return "$d->{value} second" . ($d->{value} > 1 ? "s" : "") if $d->{field} eq 'second';
      return "$d->{value} minute" . ($d->{value} > 1 ? "s" : "") if $d->{field} eq 'minute';
      return format_time(0, 0, $d->{value}, { omit_seconds_if_zero => 1 }) if $d->{field} eq 'hour';
      return num_to_ordinal($d->{value}) if $d->{field} eq 'dom';
      return $month_names{$d->{value}} // $d->{value} if $d->{field} eq 'month';
      return $day_names{$d->{value}} // $d->{value} if $d->{field} eq 'dow';
      return $d->{value};
   }

   if ($d->{kind} eq 'range') {
      my ($s, $e) = @{$d->{value}};
      if ($d->{field} eq 'hour') {
         my $from = format_time(0, 0, $s, { omit_seconds_if_zero => 1 });
         my $to   = format_time(0, 0, $e, { omit_seconds_if_zero => 1 });
         return "$from to $to";
      } else {
         my $from = $self->_render_value({ field => $d->{field}, value => $s, kind => 'value' });
         my $to   = $self->_render_value({ field => $d->{field}, value => $e, kind => 'value' });
         return "$from to $to";
      }
   }

   if ($d->{kind} eq 'list') {
      my @items = map { $self->_render_value({ field => $d->{field}, value => $_, kind => 'value' }) } @{$d->{value}};
      return join_parts(@items);
   }

   if ($d->{kind} eq 'step') {
      my $base = $d->{base};
      my $step = $d->{step};
      if ($d->{field} eq 'dom') {
         return "every " . num_to_ordinal($step) . " day of the month";
      }
      if ($d->{field} eq 'dow' && $base->{type} eq 'range') {
         my ($s, $e) = map { $_->{value} } @{$base->{children}};
         my $from = $day_names{$s} // $s;
         my $to   = $day_names{$e} // $e;
         return "every $step days between $from and $to";
      }
      return "every $step " . ($step > 1 ? "$d->{field}" . "s" : $d->{field});
   }

   if ($d->{kind} eq 'last') {
      return $d->{value} ? num_to_ordinal($d->{value}) . " to last day of every month" : "last day of every month";
   }
   if ($d->{kind} eq 'lastW') { return "last weekday of every month"; }
   if ($d->{kind} eq 'nearest_weekday') {
      return "nearest weekday to the " . num_to_ordinal($d->{value}) . " of every month";
   }
   if ($d->{kind} eq 'nth') {
      return "on the " . num_to_ordinal($d->{nth}) . " " . ($day_names{$d->{dow}} // $d->{dow}) . " of every month";
   }

   return "";
}

1;

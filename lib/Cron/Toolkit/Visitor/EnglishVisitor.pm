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

    # --- SINGLE ---
    if ($type eq 'single') {
        my $v = $node->{value};
        return undef if $v == 0 && $field =~ /^(second|minute|hour)$/;
        return { field => $field, value => $v, kind => 'value' };
    }

    # --- WILDCARD ---
    if ($type eq 'wildcard') {
        return { field => $field, value => "every $field", kind => 'context' }
            if $field =~ /^(minute|hour)$/;
        return undef;
    }

    # --- RANGE ---
    if ($type eq 'range') {
        my ($start_node, $end_node) = @{$node->{children}};
        my $start = $start_node->{value};
        my $end   = $end_node->{value};
        return { field => $field, value => [$start, $end], kind => 'range' };
    }

    # --- LIST (supports single, range, step) ---
    if ($type eq 'list') {
        my @values;
        for my $child (@{$node->{children}}) {
            if ($child->{type} eq 'single') {
                push @values, $child->{value};
            }
            elsif ($child->{type} eq 'range') {
                my ($s, $e) = map { $_->{value} } @{$child->{children}};
                push @values, $s, $e if defined $s && defined $e;
            }
            elsif ($child->{type} eq 'step') {
                my ($base, $step_node) = @{$child->{children}};
                my $step = $step_node->{value};
                my @step_vals = $self->_expand_step($base, $step, $field);
                push @values, @step_vals;
            }
        }
        return { field => $field, value => \@values, kind => 'list' };
    }

    # --- STEP (top-level) ---
    if ($type eq 'step') {
        my ($base_node, $step_node) = @{$node->{children}};
        my $step = $step_node->{value};
        my @expanded = $self->_expand_step($base_node, $step, $field);
        return { field => $field, value => \@expanded, kind => 'list' };
    }

    return undef;
}

sub _expand_step {
    my ($self, $base_node, $step, $field) = @_;
    my @expanded;

    my ($min, $max) = @{ $Cron::Toolkit::Utils::LIMITS{$field} };

    if ($base_node->{type} eq 'wildcard') {
        for (my $v = $min; $v <= $max; $v += $step) {
            push @expanded, $v;
        }
    }
    elsif ($base_node->{type} eq 'single') {
        my $start = $base_node->{value};
        $start = $min if $start < $min;
        for (my $v = $start; $v <= $max; $v += $step) {
            push @expanded, $v;
        }
    }
    elsif ($base_node->{type} eq 'range') {
        my ($s, $e) = map { $_->{value} } @{$base_node->{children}};
        $s = $min if $s < $min;
        $e = $max if $e > $max;
        for (my $v = $s; $v <= $e; $v += $step) {
            push @expanded, $v;
        }
    }

    return @expanded;
}

# ————————————————————
# JOIN: TIME — DATA-DRIVEN
# ————————————————————

sub _join_time {
    my ($self, @data) = @_;
    return "" unless @data;

    my ($sec, $min, $hour) = (0, 0, 0);
    my @context;
    my @extra;  # anything NOT second/minute/hour

    # ------------------------------------------------------------------
    # 1. Extract time fields and context
    # ------------------------------------------------------------------
    for my $d (@data) {
        if ($d->{kind} eq 'value' && $d->{field} =~ /^(second|minute|hour)$/) {
            $sec   = $d->{value} if $d->{field} eq 'second';
            $min   = $d->{value} if $d->{field} eq 'minute';
            $hour  = $d->{value} if $d->{field} eq 'hour';
        }
        elsif ($d->{kind} eq 'context') {
            push @context, $d->{value};
        }
        else {
            push @extra, $d;  # keep for later (step, dom, etc.)
        }
    }

    # ------------------------------------------------------------------
    # 2. Safe flags
    # ------------------------------------------------------------------
    my $has_every_minute = @context ? scalar(grep { /every minute/ } @context) : 0;
    my $has_every_hour   = @context ? scalar(grep { /every hour/   } @context) : 0;

    my $result = '';

    # ------------------------------------------------------------------
    # 3. SECOND OFFSET
    # ------------------------------------------------------------------
    my $second_part = '';
    if ($sec && !$has_every_minute) {
        $second_part = "$sec second" . ($sec == 1 ? '' : 's') . " past every minute";
    }

    # ------------------------------------------------------------------
    # 4. HOUR RANGES (consume from @data, not @extra)
    # ------------------------------------------------------------------
    my @hour_values;
    my @remaining_data;

    for my $d (@data) {
        if ($d->{kind} eq 'value' && $d->{field} eq 'hour') {
            push @hour_values, $d->{value};
        }
        elsif ($d->{kind} eq 'range' && $d->{field} eq 'hour') {
            push @hour_values, @{$d->{value}};
        }
        else {
            push @remaining_data, $d;
        }
    }

    if (@hour_values) {
        my @sorted = sort { $a <=> $b } @hour_values;
        my $i = 0;
        my @ranges;
        while ($i < @sorted) {
            my $start = $sorted[$i];
            my $end = $start;
            while ($i + 1 < @sorted && $sorted[$i + 1] == $end + 1) {
                $i++; $end++;
            }
            my $from = format_time(0, 0,  $start, { omit_seconds_if_zero => 1 });
            my $to   = format_time(0, 59, $end,   { omit_seconds_if_zero => 1 });
            push @ranges, $start == $end ? $from : "$from to $to";
            $i++;
        }
        $result .= " between " . join(" and ", @ranges);
    }

    # ------------------------------------------------------------------
    # 5. BASE: every minute / every hour
    # ------------------------------------------------------------------
    if ($has_every_minute && $has_every_hour) {
        $result = 'every minute after every hour' . $result;
    }
    elsif ($has_every_minute) {
        $result = 'every minute' . $result;
    }
    elsif ($has_every_hour) {
        $result = 'every hour' . $result;
    }

    # ------------------------------------------------------------------
    # 6. CONCRETE TIME (only if not part of range/step)
    # ------------------------------------------------------------------
    my $concrete_time = '';
    if (($sec || $min || $hour) && !$second_part && !@hour_values) {
        $concrete_time = format_time($sec, $min, $hour, { omit_seconds_if_zero => 1 });
        $result .= " at $concrete_time";
    }

    # ------------------------------------------------------------------
    # 7. Prepend second offset
    # ------------------------------------------------------------------
    $result = "$second_part$result" if $second_part && $result;

    # ------------------------------------------------------------------
    # 8. Append remaining values (dom, dow, step, etc.)
    # ------------------------------------------------------------------
    for my $d (@remaining_data) {
        next if $d->{kind} eq 'context';
        my $str = $self->_render_value($d);
        $result .= ", $str" if $str;
    }

    # Clean leading comma/space
    $result =~ s/^,\s+//;
    $result =~ s/^\s+//;

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

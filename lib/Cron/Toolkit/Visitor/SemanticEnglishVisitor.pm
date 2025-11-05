package Cron::Toolkit::Visitor::SemanticEnglishVisitor;
use strict;
use warnings;
use parent 'Cron::Toolkit::Visitor';

use Cron::Toolkit::Utils qw(
    num_to_ordinal format_time %month_names %day_names join_parts
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
    my ($self, $node, @results) = @_;
    return $self->_render if $node->{type} eq 'root';

    my $field = $node->{field_type} or return;
    my $m = $self->{model};

    if ($field =~ /^(second|minute|hour)$/) {
        $self->_populate_time($node, $field);
    } else {
        $self->_populate_date($node, $field);
    }
    return;
}

# ----------------------------------------------------------------------
# Populate time fields
# ----------------------------------------------------------------------
sub _populate_time {
    my ($self, $node, $field) = @_;
    my $m = $self->{model}{time};
    my $type = $node->{type};

    if ($type eq 'single') {
        $m->{$field} = { kind => 'value', value => $node->{value} };
    } elsif ($type eq 'wildcard') {
        $m->{$field} = { kind => 'every' };
    } elsif ($type eq 'range') {
        my ($s, $e) = map { $_->{value} } @{$node->{children}};
        $m->{$field} = { kind => 'range', start => $s, end => $e };
    } elsif ($type eq 'list') {
        my @items = map { $self->_render_field($_, $field) } @{$node->{children}};
        $m->{$field} = { kind => 'list', items => \@items };
    } elsif ($type eq 'step') {
        my $base = $self->_render_field($node->{children}[0], $field);
        my $step = $node->{children}[1]{value};
        $m->{$field} = { kind => 'step', base => $base, step => $step };
    }
}

# ----------------------------------------------------------------------
# Populate date fields
# ----------------------------------------------------------------------
sub _populate_date {
    my ($self, $node, $field) = @_;
    my $m = $self->{model}{date};

    return if $node->{type} eq 'unspecified';

    my $type = $node->{type};

    if ($type eq 'single') {
        $m->{$field} = { kind => 'value', value => $node->{value} };
    } elsif ($type eq 'wildcard') {
        $m->{$field} = { kind => 'every' };
    } elsif ($type eq 'range') {
        my ($s, $e) = map { $_->{value} } @{$node->{children}};
        $m->{$field} = { kind => 'range', start => $s, end => $e };
    } elsif ($type eq 'list') {
        my @items = map { $self->_render_field($_, $field) } @{$node->{children}};
        $m->{$field} = { kind => 'list', items => \@items };
    } elsif ($type eq 'step') {
        my $base = $self->_render_field($node->{children}[0], $field);
        my $step = $node->{children}[1]{value};
        $m->{$field} = { kind => 'step', base => $base, step => $step };
    } elsif ($type eq 'last') {
        my $offset = ($node->{value} =~ /L-(\d+)/) ? $1 : 0;
        $m->{dom} = { kind => 'last', offset => $offset };
    } elsif ($type eq 'lastW') {
        $m->{dom} = { kind => 'lastW' };
    } elsif ($type eq 'nearest_weekday') {
        my ($d) = $node->{value} =~ /(\d+)W/;
        $m->{dom} = { kind => 'nearest_weekday', day => $d };
    } elsif ($type eq 'nth') {
        my ($dow, $nth) = $node->{value} =~ /(\d+)#(\d+)/;
        $m->{dow} = { kind => 'nth', dow => $dow, nth => $nth };
    }
}

# ----------------------------------------------------------------------
# Helper: render field value
# ----------------------------------------------------------------------
sub _render_field {
    my ($self, $node, $field) = @_;
    return unless $node;

    my $type = $node->{type};

    if ($type eq 'single') {
        return { kind => 'value', value => $node->{value} };
    } elsif ($type eq 'wildcard') {
        return { kind => 'every' };
    } elsif ($type eq 'range') {
        my ($s, $e) = map { $_->{value} } @{$node->{children}};
        return { kind => 'range', start => $s, end => $e };
    } elsif ($type eq 'list') {
        my @items = map { $self->_render_field($_, $field) } @{$node->{children}};
        return { kind => 'list', items => \@items };
    } elsif ($type eq 'step') {
        my $base = $self->_render_field($node->{children}[0], $field);
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
    my $m = $self->{model};

    my $time = $self->_render_time($m->{time});
    my $date = $self->_render_date($m->{date});

    return $self->_combine($time, $date);
}

# ----------------------------------------------------------------------
# _render_time — FINAL, UNIFIED
# ----------------------------------------------------------------------
sub _render_time {
    my ($self, $t) = @_;
    my $s = $t->{second} // { kind => 'every' };
    my $m = $t->{minute} // { kind => 'every' };
    my $h = $t->{hour}   // { kind => 'every' };

    my @parts;

    # 1. All fixed
    if ($s->{kind} eq 'value' && $m->{kind} eq 'value' && $h->{kind} eq 'value') {
        my $time = format_time($s->{value}, $m->{value}, $h->{value});
        return $time eq '12:00:00 AM' ? "midnight every day" : "$time every day";
    }

    # 2. Unified rendering: second → minute → hour
    my @fields = (
        { data => $s, unit => 'second', plural => 'seconds', format => sub { shift } },
        { data => $m, unit => 'minute', plural => 'minutes', format => sub { sprintf(":%02d", shift) } },
        { data => $h, unit => 'hour',   plural => 'hours',   format => sub { format_time(0, 0, shift) } },
    );

    for my $i (0 .. 2) {
        my $f = $fields[$i];
        my $next = $i < 2 ? $fields[$i+1] : undef;

        my $part = $self->_render_field_part($f->{data}, $f);
        next unless $part;

        if ($next && $next->{data}{kind} eq 'every') {
            $part .= " after every $next->{unit}";
        }

        push @parts, $part;
    }

    return join(', ', @parts) || 'every hour';
}

# ----------------------------------------------------------------------
# Unified field renderer — FINAL
# ----------------------------------------------------------------------
sub _render_field_part {
    my ($self, $field, $info) = @_;
    my $kind = $field->{kind};

    if ($kind eq 'value') {
        my $val = $field->{value};
        my $unit = $info->{unit};
        my $plural = $info->{plural};
        return "$val " . ($val == 1 ? $unit : $plural);
    }

    if ($kind eq 'range') {
        my $from = $info->{format}->($field->{start});
        my $to   = $info->{format}->($field->{end});
        return "every $info->{unit} from $from to $to";
    }

    if ($kind eq 'step') {
        my $base_str = '';
        my $end_str = '';
        if ($field->{base}{kind} eq 'range') {
            $base_str = " from " . $info->{format}->($field->{base}{start});
            $end_str  = " to " . $info->{format}->($field->{base}{end});
        } elsif ($field->{base}{kind} eq 'value') {
            $base_str = " starting at " . $info->{format}->($field->{base}{value});
        }
        return "every $field->{step} $info->{unit}" . ($field->{step} > 1 ? 's' : '') . $base_str . $end_str;
    }

    if ($kind eq 'list') {
        my @rendered = map { $self->_render_field_part($_, $info) } @{$field->{items}};
        return "at " . join_parts(@rendered);
    }

    return '';
}

# ----------------------------------------------------------------------
# _render_date
# ----------------------------------------------------------------------
sub _render_date {
    my ($self, $d) = @_;
    my @parts;

    if (my $dom = $d->{dom}) {
        push @parts, $self->_render_dom($dom);
    }
    if (my $dow = $d->{dow}) {
        my $dow_str = $self->_render_dow($dow);
        push @parts, $dow_str;
    }
    if (my $month = $d->{month}) {
        my $m_str = $self->_render_month($month);
        if ($d->{dow} && $m_str) {
            $parts[-1] =~ s/ or $/ in $m_str/;
        } else {
            push @parts, $m_str;
        }
    }
    if (my $year = $d->{year}) {
        push @parts, $self->_render_year($year);
    }

    @parts = grep { $_ && length $_ } @parts;
    return join(', ', @parts) || 'every day';
}

# ----------------------------------------------------------------------
# _render_dom — fixed for list and L-1
# ----------------------------------------------------------------------
sub _render_dom {
    my ($self, $d) = @_;
    return "on the last day of every month" if $d->{kind} eq 'last' && !$d->{offset};
    return "on the " . num_to_ordinal($d->{offset}) . " to last day of every month" if $d->{kind} eq 'last';
    return "on the last weekday of every month" if $d->{kind} eq 'lastW';
    return "on the nearest weekday to the " . num_to_ordinal($d->{day}) . " of every month" if $d->{kind} eq 'nearest_weekday';
    return "on the " . num_to_ordinal($d->{value}) if $d->{kind} eq 'value';
    return "on the " . num_to_ordinal($d->{start}) . " through " . num_to_ordinal($d->{end}) if $d->{kind} eq 'range';
    if ($d->{kind} eq 'list') {
        my @items = map {
            $_->{kind} eq 'range'
                ? num_to_ordinal($_->{start}) . " through " . num_to_ordinal($_->{end})
                : num_to_ordinal($_->{value})
        } @{$d->{items}};
        return "on the " . join_parts(@items);
    }
    if ($d->{kind} eq 'step') {
        my $base = $d->{base}{kind} eq 'every' ? "the month" : "the " . num_to_ordinal($d->{base}{start}) . " to the " . num_to_ordinal($d->{base}{end});
        return "every " . num_to_ordinal($d->{step}) . " day of $base";
    }
    return '';
}

sub _render_dow {
    my ($self, $d) = @_;
    return "every " . ($day_names{$d->{value}} || $d->{value}) if $d->{kind} eq 'value';
    return "every " . ($day_names{$d->{start}} || $d->{start}) . " through " . ($day_names{$d->{end}} || $d->{end}) if $d->{kind} eq 'range';
    return "every " . join_parts(map { $day_names{$_->{value}} || $_->{value} } @{$d->{items}}) if $d->{kind} eq 'list';
    return "on the " . num_to_ordinal($d->{nth}) . " " . ($day_names{$d->{dow}} || $d->{dow}) . " of every month" if $d->{kind} eq 'nth';
    if ($d->{kind} eq 'step') {
        my $base = $d->{base}{kind} eq 'every' ? "the week" : ($day_names{$d->{base}{start}} || $d->{base}{start}) . " to " . ($day_names{$d->{base}{end}} || $d->{base}{end});
        return "every " . num_to_ordinal($d->{step}) . " day of $base";
    }
    return '';
}

sub _render_month {
    my ($self, $m) = @_;
    return $month_names{$m->{value}} || $m->{value} if $m->{kind} eq 'value';
    return ($month_names{$m->{start}} || $m->{start}) . " to " . ($month_names{$m->{end}} || $m->{end}) if $m->{kind} eq 'range';
    return join_parts(map { $month_names{$_->{value}} || $_->{value} } @{$m->{items}}) if $m->{kind} eq 'list';
    return '';
}

sub _render_year {
    my ($self, $y) = @_;
    return "in $y->{value}" if $y->{kind} eq 'value';
    return "from $y->{start} to $y->{end}" if $y->{kind} eq 'range';
    return '';
}

# ----------------------------------------------------------------------
# _combine — suppress "every day" if date is specific
# ----------------------------------------------------------------------
sub _combine {
    my ($self, $time, $date) = @_;
    return $time if !$date || $date eq 'every day';
    return "$time, $date";
}

1;

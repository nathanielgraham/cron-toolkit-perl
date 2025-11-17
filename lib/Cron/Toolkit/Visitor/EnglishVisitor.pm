package Cron::Toolkit::Visitor::EnglishVisitor;
use strict;
use warnings;
use parent 'Cron::Toolkit::Visitor';

use Cron::Toolkit::Utils qw(
    num_to_ordinal format_time %MONTH_NAMES %DAY_NAMES
    join_parts field_unit
);

# ----------------------------------------------------------------------
# Constructor
# ----------------------------------------------------------------------
sub new {
    my ( $class, %args ) = @_;
    my $self = $class->SUPER::new(%args);
    $self->{field_order} = [qw(second minute hour dom month dow year)];
    $self->{parts}       = [];          # collected sentence fragments
    return $self;
}

# ----------------------------------------------------------------------
# Entry point – called from Cron::Toolkit->describe()
# ----------------------------------------------------------------------
sub visit {
    my ( $self, $node, @child_results ) = @_;
    return $self->_fuse($node) if $node->{type} eq 'root';
    return $node;                       # leaf nodes are returned unchanged
}

# ----------------------------------------------------------------------
# Fuse the whole tree into a single English sentence
# ----------------------------------------------------------------------
sub _fuse {
    my ( $self, $root ) = @_;
    my @nodes = @{ $root->{children} || [] };

    # ------------------------------------------------------------------
    # 1. Gather data for every field
    # ------------------------------------------------------------------
    my %data;
    for my $i ( 0 .. $#nodes ) {
        my $field = $self->{field_order}[$i] or next;
        my $node  = $nodes[$i];
        my $info  = $self->_render_field( $node, $field );
        $data{$field} = $info if $info;
    }

    # ------------------------------------------------------------------
    # 2. Build time part (seconds / minutes / hours)
    # ------------------------------------------------------------------
    my $time = $self->_join_time( \%data );

    # ------------------------------------------------------------------
    # 3. Build date part (dom / month / dow / year)
    # ------------------------------------------------------------------
    my $date = $self->_join_date( \%data );

    # ------------------------------------------------------------------
    # 4. Combine
    # ------------------------------------------------------------------
    if ( $time && $date ) {
        return "$time, $date";
    }
    elsif ($time) {
        return $time =~ /every|at/ ? $time : "$time every day";
    }
    elsif ($date) {
        return $date;
    }
    else {
        return "every second";
    }
}

# ----------------------------------------------------------------------
# Render a single field node → a hash with useful keys
# ----------------------------------------------------------------------
sub _render_field {
    my ( $self, $node, $field ) = @_;
    return unless $node;

    my $type = $node->{type};

    # ------------------------------------------------------------------
    # Wildcard / Unspecified
    # ------------------------------------------------------------------
    if ( $type eq 'wildcard' ) {
        return { kind => 'every', value => "every $field" }
            if $field eq 'minute' || $field eq 'hour';
        return;
    }
    if ( $type eq 'unspecified' ) {
        return;
    }

    # ------------------------------------------------------------------
    # Simple numeric value
    # ------------------------------------------------------------------
    if ( $type eq 'single' ) {
        my $v = $node->{value};
        return if $v == 0 && $field =~ /^(second|minute|hour)$/;
        return { kind => 'value', value => $v };
    }

    # ------------------------------------------------------------------
    # Range
    # ------------------------------------------------------------------
    if ( $type eq 'range' ) {
        my ( $s, $e ) = map { $_->{value} } @{ $node->{children} };
        return { kind => 'range', start => $s, end => $e };
    }

    # ------------------------------------------------------------------
    # List
    # ------------------------------------------------------------------
    if ( $type eq 'list' ) {
        my @items = map { $self->_render_field( $_, $field ) } @{ $node->{children} };
        @items = grep { defined } @items;
        return { kind => 'list', items => \@items };
    }

    # ------------------------------------------------------------------
    # Step
    # ------------------------------------------------------------------
    if ( $type eq 'step' ) {
        my $base_node = $node->{children}[0];
        my $step_val  = $node->{children}[1]{value};
        my $base      = $self->_render_field( $base_node, $field );
        return { kind => 'step', base => $base, step => $step_val };
    }

    # ------------------------------------------------------------------
    # Quartz specials
    # ------------------------------------------------------------------
    if ( $type eq 'last' ) {
        my $offset = ( $node->{value} =~ /L-(\d+)/ ) ? $1 : 0;
        return { kind => 'last', offset => $offset };
    }
    if ( $type eq 'lastW' ) {
        return { kind => 'lastW' };
    }
    if ( $type eq 'nearest_weekday' ) {
        my ($d) = $node->{value} =~ /(\d+)W/;
        return { kind => 'nearest_weekday', day => $d };
    }
    if ( $type eq 'nth' ) {
        my ( $dow, $nth ) = $node->{value} =~ /(\d+)#(\d+)/;
        return { kind => 'nth', dow => $dow, nth => $nth };
    }

    return;    # unknown node type
}

# ----------------------------------------------------------------------
# Join the time-related fields (second / minute / hour)
# ----------------------------------------------------------------------
sub _join_time {
    my ( $self, $data ) = @_;
    my ( $sec, $min, $hour );

    # ----- seconds ----------------------------------------------------
    if ( my $s = $data->{second} ) {
        if ( $s->{kind} eq 'value' ) {
            $sec = $s->{value};
        }
        elsif ( $s->{kind} eq 'step' && $s->{base}{kind} eq 'every' ) {
            $sec = "every $s->{step} second" . ( $s->{step} > 1 ? 's' : '' );
        }
    }

    # ----- minutes ----------------------------------------------------
    my $min_desc = '';
    if ( my $m = $data->{minute} ) {
        if ( $m->{kind} eq 'every' ) {
            $min_desc = 'every minute';
        }
        elsif ( $m->{kind} eq 'value' ) {
            $min = $m->{value};
        }
        elsif ( $m->{kind} eq 'range' ) {
            $min_desc = "from $m->{start} to $m->{end} minute"
                . ( $m->{end} == 1 ? '' : 's' );
        }
        elsif ( $m->{kind} eq 'step' && $m->{base}{kind} eq 'every' ) {
            $min_desc = "every $m->{step} minute" . ( $m->{step} > 1 ? 's' : '' );
        }
    }

    # ----- hours ------------------------------------------------------
    my $hour_desc = '';
    if ( my $h = $data->{hour} ) {
        if ( $h->{kind} eq 'every' ) {
            $hour_desc = 'every hour';
        }
        elsif ( $h->{kind} eq 'value' ) {
            $hour = $h->{value};
        }
        elsif ( $h->{kind} eq 'range' ) {
            my $from = format_time( 0, 0, $h->{start}, { omit_seconds_if_zero => 1 } );
            my $to   = format_time( 0, 59, $h->{end},   { omit_seconds_if_zero => 1 } );
            $hour_desc = "$from to $to";
        }
        elsif ( $h->{kind} eq 'list' ) {
            my @times;
            for my $it ( @{ $h->{items} } ) {
                if ( $it->{kind} eq 'value' ) {
                    push @times,
                        format_time( 0, 0, $it->{value}, { omit_seconds_if_zero => 1 } );
                }
                elsif ( $it->{kind} eq 'range' ) {
                    my $f = format_time( 0, 0, $it->{start}, { omit_seconds_if_zero => 1 } );
                    my $t = format_time( 0, 59, $it->{end},   { omit_seconds_if_zero => 1 } );
                    push @times, "$f to $t";
                }
            }
            $hour_desc = join( ' and ', @times );
        }
        elsif ( $h->{kind} eq 'step' && $h->{base}{kind} eq 'every' ) {
            $hour_desc = "every $h->{step} hour" . ( $h->{step} > 1 ? 's' : '' );
        }
    }

    # ----- concrete time (when we have hour/min/sec) -----------------
    my $concrete = '';
    if ( defined $hour || defined $min || defined $sec ) {
        $concrete = format_time( $sec || 0, $min || 0, $hour || 0,
            { omit_seconds_if_zero => 1 } );
        $concrete = "at $concrete";
    }
    elsif ( $hour_desc eq 'midnight' ) {
        $concrete = 'at midnight';
    }
    elsif ( $hour_desc eq 'noon' ) {
        $concrete = 'at noon';
    }

    # ----- assemble ---------------------------------------------------
    my @bits;
    push @bits, $sec      if $sec && ref($sec) eq '';
    push @bits, $min_desc if $min_desc;
    push @bits, $hour_desc if $hour_desc;
    push @bits, $concrete if $concrete;

    return join( ' ', @bits ) || '';
}

# ----------------------------------------------------------------------
# Join the date-related fields (dom / month / dow / year)
# ----------------------------------------------------------------------
sub _join_date {
    my ( $self, $data ) = @_;
    my @parts;

    # ---- dom ---------------------------------------------------------
    if ( my $d = $data->{dom} ) {
        if ( $d->{kind} eq 'value' ) {
            push @parts, "on the " . num_to_ordinal( $d->{value} );
        }
        elsif ( $d->{kind} eq 'range' ) {
            push @parts,
                "on the "
                . num_to_ordinal( $d->{start} )
                . " through "
                . num_to_ordinal( $d->{end} );
        }
        elsif ( $d->{kind} eq 'list' ) {
            my @ords = map { num_to_ordinal( $_->{value} ) } @{ $d->{items} };
            push @parts, "on the " . join_parts(@ords);
        }
        elsif ( $d->{kind} eq 'step' && $d->{base}{kind} eq 'every' ) {
            push @parts,
                "every "
                . num_to_ordinal( $d->{step} )
                . " day of the month";
        }
        elsif ( $d->{kind} eq 'last' ) {
            my $off = $d->{offset};
            push @parts,
                $off
                ? "on the " . num_to_ordinal($off) . " to last day of every month"
                : "on the last day of every month";
        }
        elsif ( $d->{kind} eq 'lastW' ) {
            push @parts, "on the last weekday of every month";
        }
        elsif ( $d->{kind} eq 'nearest_weekday' ) {
            push @parts,
                "on the nearest weekday to the "
                . num_to_ordinal( $d->{day} )
                . " of every month";
        }
        push @parts, "of every month" unless $data->{month};
    }

    # ---- month -------------------------------------------------------
    if ( my $m = $data->{month} ) {
        my $txt;
        if ( $m->{kind} eq 'value' ) {
            $txt = $MONTH_NAMES{ $m->{value} } || $m->{value};
        }
        elsif ( $m->{kind} eq 'range' ) {
            $txt = ( $MONTH_NAMES{ $m->{start} } || $m->{start} ) . " to "
                 . ( $MONTH_NAMES{ $m->{end}   } || $m->{end} );
        }
        elsif ( $m->{kind} eq 'list' ) {
            my @names = map { $MONTH_NAMES{ $_->{value} } || $_->{value} }
                @{ $m->{items} };
            $txt = join_parts(@names);
        }
        push @parts, $txt if $txt;
    }

    # ---- dow ---------------------------------------------------------
    if ( my $w = $data->{dow} ) {
        my $txt;
        if ( $w->{kind} eq 'value' ) {
            $txt = "every " . ( $DAY_NAMES{ $w->{value} } || $w->{value} );
        }
        elsif ( $w->{kind} eq 'range' ) {
            $txt = "every "
                 . ( $DAY_NAMES{ $w->{start} } || $w->{start} )
                 . " through "
                 . ( $DAY_NAMES{ $w->{end}   } || $w->{end} );
        }
        elsif ( $w->{kind} eq 'list' ) {
            my @names = map { $DAY_NAMES{ $_->{value} } || $_->{value} }
                @{ $w->{items} };
            $txt = "every " . join_parts(@names);
        }
        elsif ( $w->{kind} eq 'nth' ) {
            $txt = "on the "
                 . num_to_ordinal( $w->{nth} )
                 . " "
                 . ( $DAY_NAMES{ $w->{dow} } || $w->{dow} )
                 . " of every month";
        }
        push @parts, $txt if $txt;
    }

    # ---- year --------------------------------------------------------
    if ( my $y = $data->{year} ) {
        my $txt;
        if ( $y->{kind} eq 'value' ) {
            $txt = "in $y->{value}";
        }
        elsif ( $y->{kind} eq 'range' ) {
            $txt = "from $y->{start} to $y->{end}";
        }
        push @parts, $txt if $txt;
    }

    return join( ", ", @parts ) || '';
}

1;

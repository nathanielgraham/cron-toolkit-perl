package Cron::Toolkit;

# VERSION
$VERSION = 1.03;

use strict;
use warnings;
use Time::Moment;
use DateTime::TimeZone;
use Cron::Toolkit::Utils qw(:all);
use Cron::Toolkit::Pattern::Single;
use Cron::Toolkit::Pattern::Wildcard;
use Cron::Toolkit::Pattern::Range;
use Cron::Toolkit::Pattern::List;
use Cron::Toolkit::Pattern::Last;
use Cron::Toolkit::Pattern::LastW;
use Cron::Toolkit::Pattern::Nth;
use Cron::Toolkit::Pattern::Unspecified;
use Cron::Toolkit::Pattern::NearestWeekday;
use Cron::Toolkit::Pattern::StepValue;
use Cron::Toolkit::Pattern::Step;

use List::Util qw(max min);
use Exporter   qw(import);
use feature 'say';

=encoding utf-8

=head1 NAME

Cron::Toolkit - Quartz-compatible cron parser with unique extensions and over 400 tests

=head1 SYNOPSIS

    use Cron::Toolkit;
    use feature qw(say);

    my $c = Cron::Toolkit->new(
        expression => "0 30 14 ? * 6-2 *",
        time_zone  => "Europe/London",
    );

    say $c->describe;
    # 2:30 PM every day from Saturday to Tuesday of every month

    # next occurence in epoch seconds
    say $c->next;

    # previous occurence in epoch seconds
    say $c->previous;

    # Question: when does February 29th next land on a Monday? 
    say Cron::Toolkit->new(expression => "0 0 0 29 2 1 *")->next;
    # Mon Feb 29 00:00:00 2044

    # See exactly what was parsed
    $c->dump_tree;
    # ┌─ second: 0
    # ├─ minute: 30
    # ├─ hour:   14
    # ├─ dom:    ?
    # ├─ month:  *
    # ├─ dow:    6-2 
    # └─ year:   *

=head1 DESCRIPTION

C<Cron::Toolkit> implements a complete, rigorously-tested cron expression parser that supports the full Quartz Scheduler syntax plus several useful extensions not found in other implementations.

Notable features include:

=over 4

=item * Full 7-field Quartz syntax (seconds and year fields)

=item * Both day-of-month and day-of-week may be specified simultaneously (AND logic)

=item * Wrapped day-of-week ranges (e.g. C<6-2> = Saturday through Tuesday)

=item * Proper Quartz-compatible DST handling

=item * Time-zone support via IANA names or fixed UTC offsets

=item * Natural-language English descriptions

=item * Complete crontab parsing with environment variable expansion

=item * Full abstract syntax tree and C<dump_tree()> for debugging

=back

=head1 RELIABILITY

The distribution ships with over 400 data-driven tests covering every supported token, leap years, DST transitions, all time zones from UTC−12 to UTC+14, and every edge case discovered during development.

If it parses, the result is correct.

=head1 UNIQUE EXTENSIONS

=over 4

=item * DOM + DOW = AND logic

Allows queries such as "next February 29 that falls on a Monday".

=item * Wrapped day-of-week ranges

6-2 matches Saturday, Sunday, Monday, Tuesday

=item * Internal day-of-week: 1–7 = Monday–Sunday

Matches L<Time::Moment> and L<DateTime>. C<as_quartz_string()> converts back to Quartz's 1=Sunday convention.

=back

=head1 FIELD REFERENCE & ALLOWED VALUES

    Field            Allowed values         Allowed special characters 
    -------------------------------------------------------------------
    Second           0–59                   *,/,-                     
    Minute           0–59                   *,/,-,
    Hour             0–23                   *,/,-,
    Day of month     1–31                   *,/,-,?,L,LW,W
    Month            1–12 or JAN–DEC        *,/,-                          
    Day of week      1–7 or MON-SUN         *,/,-,?,L,#
    Year (optional)  1970–2099              *,/,-

    Legend:
      *    wildcard
      ,    list
      -    range
      /    step
      ?    no specific value (DOM or DOW only)
      L    last (day or day-of-week)
      L-n  n to last day of the month
      nL   last n-day of the month 
      LW   last weekday of month
      nW   nearest weekday to n
      #    nth day-of-week (e.g. 3#2 = 2nd Wednesday)

    @aliases: @yearly @annually @monthly @weekly @daily @hourly (Quartz standard)

=head1 METHODS

=over 4

=item C<< Cron::Toolkit->new( expression => $expr, %options ) >>

Main constructor; auto-detects Unix vs Quartz format.

=item C<< Cron::Toolkit->new_from_unix( expression => $expr, %options ) >>

Force traditional 5-field Unix interpretation.

=item C<< Cron::Toolkit->new_from_quartz( expression => $expr, %options ) >>

Force Quartz interpretation.

=item C<< Cron::Toolkit->new_from_crontab( $string ) >>

Parse a full crontab; returns a list of C<Cron::Toolkit> objects.
Supports C<$VAR> expansion, user field, and comments.

=item C<< $c->as_string >>

Normalized 7-field representation (DOW 1–7 = Mon–Sun).

=item C<< $c->as_quartz_string >>

Quartz-compatible string (DOW 1=Sunday).

=item C<< $c->describe >>

Human-readable English description.

=item C<< $c->next( [$from_epoch] ) >>

Next occurrence after C<$from_epoch> or C<time>.

=item C<< $c->previous( [$from_epoch] ) >>

Previous occurrence before C<$from_epoch> or C<time>.

=item C<< $c->is_match( $epoch ) >>

Returns true if C<$epoch> matches the expression.

=item C<< $c->dump_tree >>

Pretty-printed abstract syntax tree (invaluable for debugging).

=item C<< $c->to_json >>

JSON representation of the object (expression, description, bounds, etc.).

=item Accessors

    $c->time_zone("Europe/Berlin")
    $c->utc_offset(+180)          # minutes
    $c->begin_epoch($epoch)
    $c->end_epoch($epoch)         # undef = no limit

=back

=head1 TIME ZONES AND DST

All calculations are performed in the configured time zone.
DST transitions follow Quartz Scheduler rules exactly:

=over 4

=item * Spring forward — times that do not exist are skipped

=item * Fall back — repeated local times fire twice

=back

=head1 BUGS AND CONTRIBUTIONS

The test suite currently contains over 400 data-driven tests covering every supported token, DST transitions, leap years, all time zones, and many edge cases — but real-world cron expressions can be surprisingly creative.

If you find:

=over 4

=item * an expression that should be valid but dies or is rejected

=item * a next/previous occurrence that is wrong

=item * a description that is misleading or unclear

=item * any behaviour that differs from Quartz Scheduler (when using Quartz syntax)

=back

...please file a bug report at
L<https://github.com/nathanielgraham/cron-toolkit-perl/issues>

Pull requests with failing test cases are especially welcome — they are the fastest way to get a fix merged.

Feature requests (e.g. more natural-language locales, RRULE export, etc.) are also very much appreciated.

Thank you!

=cut

=head1 AUTHOR

Nathaniel Graham

=head1 COPYRIGHT AND LICENSE

Copyright 2025 Nathaniel Graham

This library is free software; you may redistribute it and/or modify it
under the same terms as Perl itself.

=cut

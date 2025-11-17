package Cron::Toolkit::Pattern::Last;
use strict;
use warnings;
use parent 'Cron::Toolkit::Pattern';

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    $self->{offset} = $args{offset} if defined $args{offset};
    return $self;
}

sub type {
   return 'last';
}

sub match {
   my ($self, $value, $tm) = @_;
   my $dom           = $tm->day_of_month;
   my $days_in_month = $tm->length_of_month;
   $days_in_month -= $self->{offset} if $self->{offset};
   return $dom == $days_in_month ? 1 : 0;
}

sub to_english {
   my ($self) = @_;
   return "on the last day of every month" unless $self->{offset};
   return "on the " . num_to_ordinal($self->{offset}) . " to last day of every month";
}

1;

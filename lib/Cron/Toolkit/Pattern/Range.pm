package Cron::Toolkit::Pattern::Range;
use strict;
use warnings;
use parent 'Cron::Toolkit::Pattern';


sub type {
   return 'range';
}

sub match {
    my ($self, $value) = @_;
    my $min = $self->{children}[0]{value};
    my $max = $self->{children}[1]{value};
    return $value >= $min && $value <= $max ? 1 : 0;
}

sub to_english {
   my ($self) = @_;
   my $from = $self->{children}[0]->english_value; 
   my $to   = $self->{children}[1]->english_value; 
   return "every " . $self->english_unit . " from $from to $to";
}

1;

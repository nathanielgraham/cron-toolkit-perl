package Cron::Toolkit::Pattern::List;
use strict;
use warnings;
use parent 'Cron::Toolkit::Pattern';
use Data::Dumper;

sub type {
   return 'list';
}

sub match {
    my ($self, $value, $tm) = @_;
    #my @m = map { $_->match($value, $tm) } @{ $self->{children} };
    #print Dumper(\@m);
    return scalar (grep { $_->match($value, $tm) } @{ $self->{children} }) ? 1 : 0;
}

sub to_english {
   my ($self) = @_;
   my @items = map { $_->to_english } @{ $self->{children} };
   #print Dumper(\@items);
   return join(', ', @items);
}

1;

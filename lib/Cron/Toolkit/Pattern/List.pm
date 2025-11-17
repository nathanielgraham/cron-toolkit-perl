package Cron::Toolkit::Pattern::List;
use strict;
use warnings;
use parent 'Cron::Toolkit::Pattern';
use Data::Dumper;

sub type {
   return 'list';
}

sub to_english {
   my ($self) = @_;
   #print Dumper($self->children);

   my @items = map { $_->to_english } @{ $self->{children} };
   #print Dumper(\@items);
   return join(', ', @items);
}

1;

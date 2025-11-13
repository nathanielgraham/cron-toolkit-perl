package Cron::Toolkit::Pattern::SinglePattern;
use strict;
use warnings;
use parent 'Cron::Toolkit::Pattern::LeafPattern';
use Cron::Toolkit::Utils qw(:all);

sub is_leaf {
   return 1;
}

1;

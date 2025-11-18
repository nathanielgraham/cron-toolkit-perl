package Cron::Toolkit::Pattern::Nth;
use strict;
use warnings;
use parent 'Cron::Toolkit::Pattern';
use Cron::Toolkit::Utils qw(:all);

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    $self->{dow} = $args{dow};
    $self->{nth} = $args{nth};
    return $self;
}

sub type {
   return 'nth';
}

sub match {
   my ($self, $value, $tm) = @_;
   #my ( $dow, $nth ) = $self->value =~ /(\d+)#(\d+)/;
   my $target_dow  = $self->{dow};
   my $actual_nth  = 0;
   my $current_dom = $tm->day_of_month;
   for ( my $d = 1 ; $d <= $current_dom ; $d++ ) {
      my $test_tm = $tm->with_day_of_month($d);
      if ( $test_tm->day_of_week == $target_dow ) {
         $actual_nth++;
      }
   }
   my $is_target = ( $tm->day_of_week == $target_dow );
   return $is_target && $actual_nth == $self->{nth} ? 1 : 0;
}

sub to_english {
   my ($self) = @_;
   my $day = $DAY_NAMES{ $self->{dow} };
   my $nth = num_to_ordinal( $self->{nth} );
   return "on the $nth $day";
}

1;

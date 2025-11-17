package Cron::Toolkit::Pattern;
use strict;
use warnings;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        children => [],
    }, $class;
    $self->{field} = $args{field} if $args{field};

    return $self;
}
sub add_child {
    my ($self, $child) = @_;
    push @{$self->{children}}, $child;
}

sub children {
    my ($self) = @_;
    return $self->{children};
}

sub type {
    my ($self, $value) = @_;
    $self->{type} = $value if defined $value;
    return $self->{type};  # Return the value (either set or current)
}

sub field {
    my ($self, $value) = @_;
    $self->{field_type} = $value if defined $value;
    return $self->{field_type}; 
}

sub value {
    my ($self, $value) = @_;
    $self->{value} = $value if defined $value;
    return $self->{value};
}


1;

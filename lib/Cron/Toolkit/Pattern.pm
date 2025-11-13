package Cron::Toolkit::Pattern;
use strict;
use warnings;
use Cron::Toolkit::Visitor::EnglishVisitor;
use Cron::Toolkit::Visitor::MatchVisitor;

sub new {
    my ($class, %args) = @_;
    my $self = bless {
        type => $args{type} // die "type required",
        children => [],
    }, $class;
    $self->{field_type} = $args{field_type} if $args{field_type};

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
sub traverse {
    my ($self, $visitor) = @_;
    my $type = $self->{type};
    # Direct for range (raw in visit)
    if ($type eq 'range') {
        return $visitor->visit($self, ());
    }
    # Recurse for list/step (flags/extract)
    my @child_results = map { $_->traverse($visitor) } @{$self->{children}};
    return $visitor->visit($self, @child_results);
}
sub is_match {
    my ($self, $value, $tm) = @_;
    my $visitor = Cron::Toolkit::Visitor::MatchVisitor->new(value => $value, tm => $tm);
    return $self->traverse($visitor);
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

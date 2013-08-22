package Log::Any::Adapter::Test;
use strict;
use warnings;

# VERSION
# ABSTRACT: Backend adapter for Log::Any::Test

use Data::Dumper;
use Log::Any;
use Test::Builder;

# Pretend to inherit from Base so we look like a real Adapter class,
# but really inherit from Core which has the functionality we need
#
use Log::Any::Adapter::Core ();
{ package Log::Any::Adapter::Base }    # so perl knows about it for @ISA
our @ISA = qw(Log::Any::Adapter::Base Log::Any::Adapter::Core);

my $tb = Test::Builder->new();
my @msgs;

# All detection methods return true
#
foreach my $method ( Log::Any->detection_methods() ) {
    Log::Any->make_method( $method, sub { 1 } );
}

# All logging methods push onto msgs array
#
foreach my $method ( Log::Any->logging_methods() ) {
    Log::Any->make_method(
        $method,
        sub {
            my ( $self, $msg ) = @_;
            push(
                @msgs,
                {
                    message  => $msg,
                    level    => $method,
                    category => $self->{category}
                }
            );
        }
    );
}

# Testing methods below
#

sub msgs {
    my $self = shift;

    return \@msgs;
}

sub clear {
    my ($self) = @_;

    @msgs = ();
}

sub contains_ok {
    my ( $self, $regex, $test_name ) = @_;

    $test_name ||= "log contains '$regex'";
    my $found =
      _first_index( sub { $_->{message} =~ /$regex/ }, @{ $self->msgs } );
    if ( $found != -1 ) {
        splice( @{ $self->msgs }, $found, 1 );
        $tb->ok( 1, $test_name );
    }
    else {
        $tb->ok( 0, $test_name );
        $tb->diag( "could not find message matching $regex; log contains: "
              . $self->dump_one_line( $self->msgs ) );
    }
}

sub does_not_contain_ok {
    my ( $self, $regex, $test_name ) = @_;

    $test_name ||= "log does not contain '$regex'";
    my $found =
      _first_index( sub { $_->{message} =~ /$regex/ }, @{ $self->msgs } );
    if ( $found != -1 ) {
        $tb->ok( 0, $test_name );
        $tb->diag( "found message matching $regex: " . $self->msgs->[$found] );
    }
    else {
        $tb->ok( 1, $test_name );
    }
}

sub empty_ok {
    my ( $self, $test_name ) = @_;

    $test_name ||= "log is empty";
    if ( !@{ $self->msgs } ) {
        $tb->ok( 1, $test_name );
    }
    else {
        $tb->ok( 0, $test_name );
        $tb->diag(
            "log is not empty; contains " . $self->dump_one_line( $self->msgs ) );
        $self->clear();
    }
}

sub contains_only_ok {
    my ( $self, $regex, $test_name ) = @_;

    $test_name ||= "log contains only '$regex'";
    my $count = scalar( @{ $self->msgs } );
    if ( $count == 1 ) {
        local $Test::Builder::Level = $Test::Builder::Level + 1;
        $self->contains_ok( $regex, $test_name );
    }
    else {
        $tb->ok( 0, $test_name );
        $tb->diag(
            "log contains $count messages: " . $self->dump_one_line( $self->msgs ) );
    }
}

sub _first_index {
    my $f = shift;
    for my $i ( 0 .. $#_ ) {
        local *_ = \$_[$i];
        return $i if $f->();
    }
    return -1;
}

1;

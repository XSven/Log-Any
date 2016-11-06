use 5.008001;
use strict;
use warnings;

package Log::Any::Proxy;

# ABSTRACT: Log::Any generator proxy object
our $VERSION = '1.045';

use Log::Any::Adapter::Util ();
use overload;

sub _default_formatter {
    my ( $cat, $lvl, $format, @params ) = @_;
    return $format->() if ref($format) eq 'CODE';
    my @new_params =
      map {
           !defined($_) ? '<undef>'
          : ref($_)     ? (
	        overload::OverloadedStringify($_) ? "$_"
	      : Log::Any::Adapter::Util::dump_one_line($_)
	    )
          : $_
      } @params;
    # Perl 5.22 adds a 'redundant' warning if the number parameters exceeds
    # the number of sprintf placeholders.  If a user does this, the warning
    # is issued from here, which isn't very helpful.  Doing something
    # clever would be expensive, so instead we just disable warnings for
    # the final line of this subroutine.
    no warnings;
    return sprintf( $format, @new_params );
}

sub new {
    my $class = shift;
    my $self = { formatter => \&_default_formatter, @_ };
    unless ( $self->{adapter} ) {
        require Carp;
        Carp::croak("$class requires an 'adapter' parameter");
    }
    unless ( $self->{category} ) {
        require Carp;
        Carp::croak("$class requires an 'category' parameter")
    }
    bless $self, $class;
    $self->init(@_);
    return $self;
}

sub clone {
    my $self = shift;
    return (ref $self)->new( %{ $self }, @_ );
}

sub init { }

for my $attr (qw/adapter filter formatter prefix/) {
    no strict 'refs';
    *{$attr} = sub { return $_[0]->{$attr} };
}

my %aliases = Log::Any::Adapter::Util::log_level_aliases();

# Set up methods/aliases and detection methods/aliases
foreach my $name ( Log::Any::Adapter::Util::logging_methods(), keys(%aliases) )
{
    my $realname    = $aliases{$name} || $name;
    my $namef       = $name . "f";
    my $is_name     = "is_$name";
    my $is_realname = "is_$realname";
    my $numeric     = Log::Any::Adapter::Util::numeric_level($realname);
    no strict 'refs';
    *{$is_name} = sub {
        my ($self) = @_;
        return $self->{adapter}->$is_realname;
    };
    *{$name} = sub {
        my ( $self, @parts ) = @_;
        my $message = join(" ", grep { defined($_) && length($_) } @parts );
        if ( length $message ) {
            $message = $self->{filter}->( $self->{category}, $numeric, $message )
              if defined $self->{filter};
            if ( defined $message and length $message ) {
                $message = "$self->{prefix}$message"
                  if defined $self->{prefix} && length $self->{prefix};
                $self->{adapter}->$realname($message);
            }
        }
        return $message if defined wantarray;
    };
    *{$namef} = sub {
        my ( $self, @args ) = @_;
        return unless $self->{adapter}->$is_realname;
        my $message =
          $self->{formatter}->( $self->{category}, $numeric, @args );
        return unless defined $message and length $message;
        return $self->$name($message);
    };
}

1;

=head1 SYNOPSIS

    # prefix log messages
    use Log::Any '$log', prefix => 'MyApp: ';

    # transform log messages
    use Log::Any '$log', filter => \&myfilter;

    # format with String::Flogger instead of the default
    use String::Flogger;
    use Log::Any '$log', formatter => sub {
        my ($cat, $lvl, @args) = @_;
        String::Flogger::flog( @args );
    };

    # create a clone with different attributes
    my $bar_log = $log->clone( prefix => 'bar: ' );

=head1 DESCRIPTION

Log::Any::Proxy objects are what modules use to produce log messages.  They
construct messages and pass them along to a configured adapter.

=head1 USAGE

=head2 Simple logging

Your library can do simple logging using logging methods corresponding to
the log levels (or aliases):

=for :list
* trace
* debug
* info (inform)
* notice
* warning (warn)
* error (err)
* critical (crit, fatal)
* alert
* emergency

Pass a string to be logged.  Do not include a newline.

    $log->info("Got some new for you.");

The log string will be transformed via the C<filter> attribute (if any) and
the C<prefix> (if any) will be prepended. Returns the transformed log string.

B<NOTE>: While you are encouraged to pass a single string to be logged, if
multiple arguments are passed, they are concatenated with a space character
into a single string before processing.  This ensures consistency across
adapters, some of which may support multiple arguments to their logging
functions (and which concatenate in different ways) and some of which do
not.

=head2 Advanced logging

Your library can do advanced logging using logging methods corresponding to
the log levels (or aliases), but with an "f" appended:

=for :list
* tracef
* debugf
* infof (informf)
* noticef
* warningf (warnf)
* errorf (errf)
* criticalf (critf, fatalf)
* alertf
* emergencyf

When these methods are called, the adapter is first checked to see if it is
logging at that level.  If not, the method returns without logging.

Next, arguments are transformed to a message string via the C<formatter>
attribute.

The default formatter first checks if the first log argument is a code
reference.  If so, it will executed and the result used as the formatted
message. Otherwise, the formatter acts like C<sprintf> with some helpful
formatting.

Finally, the message string is logged via the simple logging functions,
which can transform or prefix as described above. The transformed log
string is then returned.

=attr adapter

A L<Log::Any::Adapter> object to receive any messages logged.  This is
generated by L<Log::Any> and can not be overridden.

=attr category

The category name of the proxy.  If not provided, L<Log::Any> will set it
equal to the calling when the proxy is constructed.

=attr filter

A code reference to transform messages before passing them to a
Log::Any::Adapter.  It gets three arguments: a category, a numeric level
and a string.  It should return a string to be logged.

    sub {
        my ($cat, $lvl, $msg) = @_;
        return "[$lvl] $msg";
    }

If the return value is undef or the empty string, no message will be
logged.  Otherwise, the return value is passed to the logging adapter.

Numeric levels range from 0 (emergency) to 8 (trace).  Constant functions
for these levels are available from L<Log::Any::Adapter::Util>.

=attr formatter

A code reference to format messages given to the C<*f> methods (C<tracef>,
C<debugf>, C<infof>, etc..)

It get three or more arguments: a category, a numeric level and the list
of arguments passsed to the C<*f> method.  It should return a string to
be logged.

    sub {
        my ($cat, $lvl, $format, @args) = @_;
        return sprintf($format, @args);
    }

The default formatter does the following:

=for :list
* if the first argument is a code reference, it is executed and the result
  returned
* otherwise, it acts like C<sprintf>, except that undef arguments are
  changed to C<< <undef> >> and any references or objects are dumped via
  L<Data::Dumper> (but without newlines).

Numeric levels range from 0 (emergency) to 8 (trace).  Constant functions
for these levels are available from L<Log::Any::Adapter::Util>.

=attr prefix

If defined, this string will be prepended to all messages.  It will not
include a trailing space, so add that yourself if you want.  This is less
flexible/powerful than L</filter>, but avoids an extra function call.

=cut

# vim: ts=4 sts=4 sw=4 et tw=75:

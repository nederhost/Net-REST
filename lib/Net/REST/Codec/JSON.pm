package Net::REST::Codec::JSON;

use strict;
use warnings;

use JSON::XS;

sub new {
  my $class = shift;
  bless {
    json => JSON::XS->new->ascii->relaxed->allow_nonref
  }, $class;
}

sub default_content_type { 'application/json' }

sub parse {
  my $self = shift;
  my ( $method, $content_type, $json ) = @_;
  return eval { $self->{json}->decode ( $json ) };
}

sub serialize {
  my $self = shift;
  my ( $method, $data ) = @_;
  return ( 'application/json', $self->{json}->encode ( $data ));
}

1;

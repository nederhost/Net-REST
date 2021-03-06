package Net::REST::Codec::JSON;

use strict;
use warnings;

use JSON;

sub new {
  my $class = shift;
  bless {
    json => JSON->new->ascii->relaxed->allow_nonref
  }, $class;
}

sub default_content_type { 'application/json' }

sub parse {
  my $self = shift;
  my ( $method, $content_type, $json ) = @_;
  if ( $content_type =~ /json|javascript/ ) {
    return eval { $self->{json}->decode ( $json ) };
  } else {
    return $json;
  }
}

sub serialize {
  my $self = shift;
  my ( $method, $data ) = @_;
  return ( 'application/json', $self->{json}->encode ( $data ));
}

1;

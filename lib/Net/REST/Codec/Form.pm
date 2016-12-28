package Net::REST::Codec::Form;

use strict;
use warnings;

use Carp;
use URI::Encode;

sub new {
  my $class = shift;
  bless {
    encode => URI::Encode->new ( { encode_reserved => 1 } )
  }, $class;
}

sub parse { croak "Not implemented" }

sub serialize {
  my $self = shift;
  my ( $method, $data ) = @_;
  
  return ( 
    'application/x-www-form-urlencoded', 
    join ( 
      '&',
      map {
        $_ . '=' . $self->{encode}->encode ( $data->{$_} )
      } ( keys %{$data} )
    )
  );
}

1;

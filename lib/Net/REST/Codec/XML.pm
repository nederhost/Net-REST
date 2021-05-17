package Net::REST::Codec::XML;

use strict;
use warnings;

use Carp;
use XML::Fast;

sub new {
  my $class = shift;
  my ( $config ) = @_;

  bless {
    config => shift,
  }, $class;  
}

sub parse {
  my $self = shift;
  my ( $method, $content_type, $xml ) = @_;

  return { %{ XML::Fast::xml2hash $xml }};

}

sub serialize {
  croak "Serialisation not supported by this Codec";
}

1;

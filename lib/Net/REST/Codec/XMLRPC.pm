package Net::REST::Codec::XMLRPC;

use strict;
use warnings;

use Carp;
use Frontier::RPC2;

sub new {
  my $class = shift;
  bless {
    frontier => Frontier::RPC2->new
  }, $class;
}

sub parse { 
  my $self = shift;
  my ( $method, $content_type, $data ) = @_;  
  return $self->{frontier}->decode ( $data );
}

sub serialize {
  my $self = shift;
  my ( $method, $data ) = @_;  
  return ( 'application/xml', $self->{frontier}->encode_call ( $method, @{$data} ));
}

1;

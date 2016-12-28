package Net::REST::Common::XMLRPC;

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::XMLRPC;

sub _init {
  my $self = shift;
  
  my $xmlrpc = Net::REST::Codec::XMLRPC->new;
  $self->_set (
    request => {
      serializer => $xmlrpc,
      methods => {
        '*' => { http => 'post' }
      }
    },
    response => {
      parser => $xmlrpc
    }
  );
}

sub _get_error {
  my $self = shift;
  my ( $r ) = @_;
  
  if ( $r->{type} eq 'fault' ) {
    return {
      error => $r->{value}[0]{faultCode},
      errormessage => $r->{value}[0]{faultString}
    };
  }
  return undef;
}

sub _get_value {
  my $self = shift;
  my ( $r ) = @_;
  if ( $r->{type} eq 'response' ) {
    return $r->{value}[0];
  }
  return undef;
}

sub _process_parameters { shift; [ @_ ] };

1;

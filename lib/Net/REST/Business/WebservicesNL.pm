package Net::REST::Business::WebservicesNL;

use strict;
use warnings;

use base 'Net::REST::Common::XMLRPC';
use Carp;
use Net::REST::Codec::XML;
use URI::Encode;

sub _init {
  my $self = shift;
  $self->SUPER::_init ( @_ );
  
  my %param = @_;
  if ( $param{username} && $param{password} ) {
    $self->{webservicesnl} = {
      username => $param{username},
      password => $param{password}
    };
  } else {
    croak "Required parameters username and password not specified";
  }
  
  $self->_set (
    default_base_url => 'https://ws1.webservices.nl/xmlrpc/utf-8',
  );
}

#
# The _hook_pre_execute adds the required username and password parameters
# to all requests.
#

sub _hook_pre_execute {
  my $self = shift;
  my ( $http_method, $method, $param ) = @_;
  
  unshift @{$param}, $self->{webservicesnl}{password};
  unshift @{$param}, $self->{webservicesnl}{username};
}

1;

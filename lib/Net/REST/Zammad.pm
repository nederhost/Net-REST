package Net::REST::Zammad;

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::JSON;

sub _init {
  my $self = shift;
  my %param = @_;
  
  my $json = Net::REST::Codec::JSON->new;

  $self->_set (
    base_url_ends_with => '/',

    api_key => {
      include_as => 'header',
      name => 'Authorization',
      format => 'Token token=%s'
    },

    request => {
      serializer => $json,
      content_type => 'application/json',		# an override for the content type; serializers will have sensible defaults
      methods => {
        '*' 		=> { route => ['&', '*'] },
        'post' 		=> { http => 'post', 	pass_arguments => 1 },
        'update'	=> { http => 'put',	pass_arguments => 1 },
        'get'		=> { http => 'get', 	route => ['#0'] },
        'list'		=> { http => 'get',	pass_arguments => 1 }
      }
    },
    
    response => { 
      parser => $json,
#      path_as_error => '/code'				# if the errors are returned as regular responses (or contained in HTTP error responses)
    },

  );
}

#
# Implement an internal _on_behalf_of parameter which allows us to execute
# requests on behalf of another user by setting a special header.
#

sub _hook_pre_serialisation {

  my $self = shift;
  my ( $req, $method, $param ) = @_;

  if ( ref $param eq 'HASH' ) {
    my $uid = $param->{_on_behalf_of};
    delete $param->{_on_behalf_of};
    if ( $uid ) {
      $req->headers->header ( 'X-On-Behalf-Of' => $uid );
    }
  }

}

1;

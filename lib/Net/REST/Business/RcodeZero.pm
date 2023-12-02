package Net::REST::Business::RcodeZero;

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::JSON;

sub _init {
  my $self = shift;
  
  my $json = Net::REST::Codec::JSON->new;
  
  $self->_set (
    default_base_url => 'https://my.rcodezero.at/api/v2/',# can be overridden by user
    base_url_ends_with => '/',

    api_key => {					# if present, requires an API key and indicates where to put it
      include_as => 'header',				# or 'argument'
      name => 'Authorization',				# name of the header or argument to use
      format => 'Bearer %s'				# how to format the API key (sprintf format string)
    },
    
    request => {
      serializer => $json,
      content_type => 'application/json',		# an override for the content type; serializers will have sensible defaults
      methods => {
        '*' 		=> { route => ['&', '*'] },
        'post' 		=> { http => 'post', 	pass_arguments => 1 },
        'create'	=> { http => 'post', 	pass_arguments => 1 },
        'replace'	=> { http => 'put', 	pass_arguments => 1 },
        'update'	=> { http => 'patch', 	pass_arguments => 1 }, 
        'get'		=> { http => 'get', 	route => ['#0'] },
        'list'		=> { http => 'get',  	pass_arguments => 1 },
        'delete' 	=> { http => 'delete',	route => ['#0'] },
      }
    },
    
    response => { 
      parser => $json
    },

  );
}

sub _hook_post_request_error {
  my $self = shift;
  my ( $error ) = @_;
  
  if ( $error->{error}{content} ) {
    $error->{error} = Net::REST::Codec::JSON->new->parse ( '', $error->{headers}{'content-type'}, $error->{error}{content} )
  }
}

1;

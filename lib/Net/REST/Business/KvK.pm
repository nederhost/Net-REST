package Net::REST::Business::KvK;

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::JSON;

sub _init {
  my $self = shift;
  
  my $json = Net::REST::Codec::JSON->new;
  
  $self->_set (
    default_base_url => 'https://api.kvk.nl/api/v1/',	# can be overridden by user
    base_url_ends_with => '/',

    api_key => {					# if present, requires an API key and indicates where to put it
      include_as => 'header',				# or 'argument'
      name => 'apikey',					# name of the header or argument to use
      format => '%s'					# how to format the API key (sprintf format string)
    },
    
    request => {
      serializer => $json,
      content_type => 'application/json',		# an override for the content type; serializers will have sensible defaults
      methods => {
        '*' 		=> { route => ['&', '*'] },
        'post' 		=> { http => 'post', pass_arguments => 1 },
        'create'	=> { http => 'post', pass_arguments => 1 },
        'update'	=> { http => 'post', pass_arguments => 1 },
        'reset'		=> { http => 'post', pass_arguments => 1 },
        'get'		=> { http => 'get', 	route => ['#0'] },
        'list'		=> { http => 'get',  pass_arguments => 1 },
        'delete' 	=> { http => 'delete',	route => ['#0'] },
        'cancel'	=> { http => 'delete', 	route => ['#0'] },
        'revoke' 	=> { http => 'delete',	route => ['#0'] }
      }
    },
    
    response => { 
      parser => $json,
#      path_as_error => '/error'				# if the errors are returned as regular responses (or contained in HTTP error responses)
    },

  );
}

1;

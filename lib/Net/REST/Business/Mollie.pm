package Net::REST::Business::Mollie;

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::JSON;

sub _init {
  my $self = shift;
  
  my $json = Net::REST::Codec::JSON->new;
  
  $self->_set (
    default_base_url => 'https://api.mollie.nl/v1/',	# can be overridden by user
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
        'post' 		=> { http => 'post' },
        'create'	=> { http => 'post' },
        'update'	=> { http => 'post' },
        'reset'		=> { http => 'post' },
        'get'		=> { http => 'get', 	route => ['#0'] },
        'list'		=> { http => 'get' },
        'delete' 	=> { http => 'delete',	route => ['#0'] },
        'cancel'	=> { http => 'delete', 	route => ['#0'] },
        'revoke' 	=> { http => 'delete',	route => ['#0'] }
      }
    },
    
    response => { 
      parser => $json,
      path_as_error => '/error'				# if the errors are returned as regular responses (or contained in HTTP error responses)
    },

  );
}

1;

package Net::REST::WordPress;

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

    request => {
      serializer => $json,
      content_type => 'application/json',		# an override for the content type; serializers will have sensible defaults
      methods => {
        '*' 		=> { route => ['&', '*'] },
        'post' 		=> { http => 'post', 	pass_arguments => 1 },
        'create'	=> { http => 'post', 	pass_arguments => 1 },
        'update'	=> { http => 'patch',	pass_arguments => 1 },
        'get'		=> { http => 'get', 	route => ['#0'] },
        'list'		=> { http => 'get',	pass_arguments => 1 },
        'delete' 	=> { http => 'delete',	route => ['#0'] }
      }
    },
    
    response => { 
      parser => $json,
      path_as_error => '/code'				# if the errors are returned as regular responses (or contained in HTTP error responses)
    },

  );
}

#
# If WordPress returns informational headers, we store those.
#

sub _hook_post_request {
  my $self = shift;
  my ( $response ) = @_;
  
  $self->{global_state}{_wordpress}{meta} = {};
  foreach ( 'Total', 'TotalPages' ) {
    $self->{global_state}{_wordpress}{meta}{lc ( $_ )} = $response->header ( 'X-WP-' . $_ );
  }
}

sub get_meta {
  shift->{global_state}{_wordpress}{meta};
}

1;

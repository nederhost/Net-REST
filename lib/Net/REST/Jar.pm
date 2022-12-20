package Net::REST::Jar;

# Additional arguments for the Jar client:
#
# clientname -- the registered name of this client (the owner of the
#   clientkey)
# clientkey -- the key assigned to this specific client (this does not
#   authorize a user usually)
# origin -- an IP address to provide as the origin for any requests (can
#   also be set or updated with set_origin)

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::JSON;

sub _init {
  my $self = shift;
  my %param = @_;
  
  my $json = Net::REST::Codec::JSON->new;
  
  unless ( $param{clientkey} && $param{clientname} ) {
    die "Specify a clientkey and clientname";
  }
  
  # Set the default headers; the x-jar-clientkey key authorizes the client
  # and not the user.  However, some clients may have extensive access to
  # the system without authorization so it is still a secret.

  $self->{default_headers}{'x-jar-clientkey'} = sprintf( '%s %s', $param{'clientname'}, $param{'clientkey'} );  
  if ( $param{origin} ) {
    $self->{default_headers}{'x-jar-origin'} = $param{origin};
  }

  $self->_set (
    base_url_ends_with => '/',
    
    request => {
      serializer => $json,
      content_type => 'application/json',		# an override for the content type; serializers will have sensible defaults
      methods => {
        '*' 		=> { route => ['&', '*'] },
        'post' 		=> { http => 'post', 	pass_arguments => 1 },
        'create' 	=> { http => 'post', 	pass_arguments => 1 },
        'update'	=> { http => 'put',	pass_arguments => 1 },
        'get'		=> { http => 'get', 	route => ['#0'] },
        'query'		=> { http => 'get', 	pass-arguments => 1 },
        'list'		=> { http => 'get',	pass_arguments => 1 }
      }
    },
    
    response => { 
      parser => $json,
    },

  );
}

sub get_jar_error {
  my $self = shift;
  return Net::REST::Codec::JSON->new->parse ( 
    undef,
    'application/json',
    $self->{global_state}{error}{error}{content} 
  );
}

sub set_origin {
  # Update the origin for requests.
  my $self = shift;
  my ( $origin ) = @_;
  
  if ( $origin ) {
    $self->{default_headers}{'x-jar-origin'} = $origin;
  } else {
    delete $self->{default_headers}{'x-jar-origin'};
  }
}

1;

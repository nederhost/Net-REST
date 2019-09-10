package Net::REST::Business::SorryApp;

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::Form;
use Net::REST::Codec::JSON;

sub _init {
  my $self = shift;

  my $json = Net::REST::Codec::JSON->new;

  $self->_set (
    default_base_url => 'https://api.sorryapp.com/v1/', # can be overridden by user
    base_url_ends_with => '/',

    api_key => {                                        # if present, requires an API key and indicates where to put it
      include_as => 'header',                           # or 'argument'
      name => 'Authorization',                          # name of the header or argument to use
      format => 'Bearer %s'                             # how to format the API key (sprintf format string)
    },

    request => {
      serializer => Net::REST::Codec::Form->new,
      methods => {
        '*'             => { route => ['&', '*'] },
        'post'          => { http => 'post',    pass_arguments => 1 },
        'create'        => { http => 'post',    pass_arguments => 1 },
        'update'        => { http => 'patch',   pass_arguments => 1 },
        'get'           => { http => 'get',     pass_arguments => 1,    route => ['#0'] },
        'list'          => { http => 'get',     pass_arguments => 1 },
        'delete'        => { http => 'delete',                          route => ['#0'] },
      }
    },

    response => {
      parser => Net::REST::Codec::JSON->new,
      path_as_error => '/error'                         # if the errors are returned as regular responses (or contained in HTTP error responses)
    },

  );
}

# SorryApp allows for parameters to be specified more than once (for
# filtering).

sub _process_parameters { shift; return [ @_ ]; }

1;

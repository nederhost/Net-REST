package Net::REST::Business::UptimeRobot;

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::Form;
use Net::REST::Codec::JSON;

sub _init {
  my $self = shift;
  
  my $json = Net::REST::Codec::JSON->new;
  
  $self->_set (
    default_base_url => 'https://api.uptimerobot.com/v2/',	# can be overridden by user
    base_url_ends_with => '/',

    api_key => {					# if present, requires an API key and indicates where to put it
      include_as => 'argument',				# or 'argument'
      name => 'api_key'					# name of the header or argument to use
    },
    
    request => {
      serializer => Net::REST::Codec::Form->new,
      methods => {
        '*' => { http => 'post', pass_arguments => 1, route => ['&'] },
      }
    },
    
    response => { 
      parser => Net::REST::Codec::JSON->new,
      path_as_error => '/error'				# if the errors are returned as regular responses (or contained in HTTP error responses)
    },

  );
}

sub _hook_pre_execute {
  my $self = shift;
  my ( $http_method, $method, $param ) = @_;
  
  $param->{format} = 'json';
}

1;

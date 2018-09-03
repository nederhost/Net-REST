package Net::REST::Business::Moneybird;

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::JSON;

use HTTP::Date;

sub _init {
  my $self = shift;
  my %param = @_;
  
  if ( my $count = $param{autoretry_after_tmr} ) {			# autoretry after a 'too many requests' error?
    $self->{moneybird}{autoretry_after_tmr} = $count;
  }
  
  my $json = Net::REST::Codec::JSON->new;
  
  $self->_set (
    default_base_url => 'https://moneybird.com/api/v2/',	# can be overridden by user
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
        'update'	=> { http => 'patch',	pass_arguments => 1 },
        'get'		=> { http => 'get', 	route => ['#0'] },
        'list'		=> { http => 'get',	pass_arguments => 1 },
        'delete' 	=> { http => 'delete',	route => ['#0'] },
      }
    },
    
    response => { 
      parser => $json,
      path_as_error => '/error'				# if the errors are returned as regular responses (or contained in HTTP error responses)
    },

  );
}

sub execute {
  my $self = shift;
  my @arg = @_;
  my $result = $self->SUPER::execute ( @arg );
  if ( $self->{moneybird}{autoretry_after_tmr} ) {
    if ( my $error = $self->error ) {
      if (( $error->type eq 'http' ) && ( $error->code == 429 )) {	# Too many requests; wait and then retry.
        my $count = $self->{moneybird}{autoretry_after_tmr};
        while ( $count > 0 ) {
          my $wait = $error->headers->{'Retry-After'};
          if ( $wait && ( $wait !~ /^[0-9]+$/ )) {			# Got a HTTP timestamp
            $wait = gmtime ( localtime ) - HTTP::Date::str2time ( $wait, 'GMT' );
          }
          $wait = 60 unless ( $wait && ( $wait > 0 ));			# By default we'll wait a minute.
          warn "API said: " . $error->code . ' ' . $error->message. "; autoretrying after $wait second(s).\n";
          sleep $wait + 1;
          $count--;
          $result = $self->SUPER::execute ( @arg );
          $error = $self->error;
          last unless ( $error );
        }
      }
    }
  }
  
  return $result;
  
}

1;

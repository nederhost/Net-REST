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
        'upload'	=> { http => 'post', 	pass_arguments => 1 },
      }
    },
    
    response => { 
      parser => $json,
      path_as_error => '/error'				# if the errors are returned as regular responses (or contained in HTTP error responses)
    },

  );
}

sub download {						# A bit hacky, but this is the 'nicest' way to download files for now.
  my $self = shift;
  my $param = $self->_process_parameters ( @_ );

  while ( my ( $key, $value ) = each %{$self->{default_arguments} || {}} ) {
    $param->{$key} = $value unless ( exists $param->{$key} );
  }

  my $uri = URI->new ( $self->{route} );
  my $req = HTTP::Request->new ( 'GET' => $uri );

  $req->headers->header ( %{$self->{default_headers}} ) if ( %{$self->{default_headers}} );

  # If arguments are given, serialise and add to request.
  $param = undef if (( ref $param eq 'HASH' ) && ( ! %{$param} ));
  if ( $param ) {
    $uri->query_form ( %{$param} );
    $req->uri ( $uri );
  }

  if ( $self->{debug} ) {
    print STDERR $req->dump ( prefix => "$self >>> ", maxlength => 10240, no_content => '' );
    print STDERR "$self ---\n";
  }

  # Now we execute the request.
  if ( my $response = $self->{ua}->request ( $req )) {

    if ( $self->{debug} ) {
      print STDERR $response->dump ( prefix => "$self <<< ", maxlength => 10240, no_content => '' );
      print STDERR "$self ---\n";
    }
      
    return $response;
  }

  # If we're here something went wrong.
  return undef;

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

sub synchronize_all {								# Method to use the synchronization API to get all matching elements
  my $self = shift;
  my @arg = @_;
  
  if ( my $s = $self->synchronization->list ( @arg )) {
    my @item_ids = map { $_->{id} } @{$s};
    my @items;
    while ( @item_ids ) {
      my @this_round_ids = splice @item_ids, 0, ( @item_ids > 100 ? 99 : $#item_ids );
      if ( my $these_items = $self->synchronization->post ( ids => \@this_round_ids )) {
        push @items, @{$these_items};
      } else { return undef }
    }
    return \@items;
  } else {
    return $self->list ( @arg );
  }
}

sub _hook_pre_serialisation {
  my $self = shift;
  my ( $req, $method, $param ) = @_;
  
  if ( $method eq 'upload' ) {		# We're uploading a file
    $req->content_type ( 'multipart/mixed' );
    foreach my $fieldname ( keys %{$param} ) {
    
      my ( $filename, $content_type, $content );
      if ( ref $param->{$fieldname} eq 'HASH' ) {
        $filename = $param->{$fieldname}{filename};
        $content_type = $param->{$fieldname}{content_type};
        if ( $param->{$fieldname}{content} ) {
          $content = $param->{$fieldname}{content};
        } else {
          open ( FILE, $param->{$fieldname}{filename} ) or die 'Cannot open ' . $param->{$fieldname}{filename} . ' for reading: ' . $!;
          $content = join ( '', <FILE> );
          close ( FILE );
        }
      }
      
      $filename ||= $fieldname;
      foreach ( $filename, $fieldname ) { s/"//g; }
    
      $req->add_part (
        HTTP::Message->new (
          [
            'Content-Disposition' => 'attachment; filename="' . $filename . '"; name="' . $fieldname . '"',
            'Content-Length' => length ( $content ),
            ( $content_type ? ( 'Content-Type' => $content_type ) : ())
          ],
          $content
        )
      );
      delete $param->{$fieldname};
    }
  }
}

1;

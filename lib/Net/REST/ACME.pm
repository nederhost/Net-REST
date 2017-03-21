# Some code taken from or inspired by Crypt::LE.

package Net::REST::ACME;

use strict;
use warnings;

use base 'Net::REST';
use Net::REST::Codec::JSON;

use Carp;
use Crypt::Format;
use Crypt::OpenSSL::Bignum;
use Crypt::OpenSSL::RSA;
use Digest::SHA;
use JSON::XS;
use MIME::Base64;

our $AUTOLOAD;
our $replay_nonce;

sub _init {
  my $self = shift;
  my %param = @_;
  
  my $json = Net::REST::Codec::JSON->new;
  
  $self->{acme}{jws_json} = JSON::XS->new->canonical->allow_nonref;
  if ( $param{key} ) {
    if ( $self->{acme}{key} = Crypt::OpenSSL::RSA->new_private_key ( $param{key} )) {
    
      $self->{acme}{key}->use_pkcs1_padding;
      $self->{acme}{key}->use_sha256_hash;
    
      my ($n, $e) = $self->{acme}{key}->get_key_parameters;
      foreach ($n, $e) {
        $_ = $_->to_hex;
        $_ = "0$_" if length($_) % 2;
      }
      $self->{acme}{jwk} = {
        kty => 'RSA',
        n => $self->_encode_base64url ( pack ( 'H*', $n )),
        e => $self->_encode_base64url ( pack ( 'H*', $e ))
      };
      
      $self->{acme}{fingerprint} = $self->_encode_base64url ( Digest::SHA::sha256 ( $self->{acme}{jws_json}->encode ( $self->{acme}{jwk} )));
      
    } else { croak "Cannot load RSA key from $param{key}" }
  } else {
    croak "Required parameter key not specified";
  }
  
  $self->_set (
    default_base_url => $param{live} ? 'https://acme-v01.api.letsencrypt.org/' : 'https://acme-staging.api.letsencrypt.org/',
    base_url_ends_with => '/',

    request => {
      serializer => $json,
      content_type => 'application/json',		# an override for the content type; serializers will have sensible defaults
      methods => {
        '*' 		=> { http => 'get', route => ['&'] },
        'post' 		=> { http => 'post', pass_arguments => 1 },
        'get'		=> { http => 'get', 	route => ['#0'] },
      }
    },
    
    response => { 
      parser => $json,
      path_as_error => '/error'				# if the errors are returned as regular responses (or contained in HTTP error responses)
    },

  );
  
}

sub do {
  my $self = shift;
  my ( $req, $param ) = @_;
  
  unless ( $self->{directory} ) {
    $self->{directory} = $self->route ( 'directory' )->get;
  }
  
  if ( $self->{directory}{$req} ) {
    $param->{resource} = $req;
    return $self->route ( $self->{directory}{$req} )->post ( %{$param} );
  } else {
    croak "Request not in directory: $req";
  }
  
}

sub get_object {
  my $self = shift;
  my ( $uri ) = @_;
  
  my $object = $self->route ( $uri );
  my $data = $object->get();  
  return Net::REST::ACME::Object->new ( $object, $uri, $data );  
}

sub encode_pem {
  my $self = shift;
  my ( $pem ) = @_;
  
  return $self->_encode_base64url ( Crypt::Format::pem2der ( $pem ));
}

# Our own private subroutine for this, because the CentOS standard
# MIME::Base64 does not do this for us.
sub _encode_base64url {
  shift;
  my $e = MIME::Base64::encode_base64 ( shift, '' );
  $e =~ s/=+\z//;
  $e =~ tr[+/][-_];
  return $e;
}

# Find objects in output from the ACME system and automatically instantiate
# them.
sub _find_objects {
  my $self = shift;  
  if ( ref $_[0] eq 'HASH' ) {
    if ( $_[0]->{uri} ) {		# An object!
      $_[0] = Net::REST::ACME::Object->new ( $self, $_[0]->{uri}, $_[0] );
    } else {
      foreach ( values %{$_[0]} ) {
        $self->_find_objects ( $_ ) if ( ref $_ );
      }
    }
  } elsif ( ref $_[0] eq 'ARRAY' ) {
    foreach ( @{$_[0]} ) {
      $self->_find_objects ( $_ ) if ( ref $_ );
    }
  }
}

sub _get_value {
  ( $_[0]->{global_state}{error} && ( ! ref $_[1] )) ? undef : $_[1];
}

sub _hook_pre_request {
  my $self = shift;
  my ( $req ) = @_;

  if ( my $content = $req->content ) {
  
    if ( $self->{debug} ) {
      print STDERR "$self >>> PAYLOAD BEGIN\n" . $content . "\n" . "$self >>> PAYLOAD END\n";
    }
  
    # Add JWS signature  
    my $json = $self->_encode_base64url ( $content );
    my $header = $self->_encode_base64url ( '{"nonce":"' . $Net::REST::ACME::replay_nonce . '"}' );    
    my $sig = $self->_encode_base64url ( $self->{acme}{key}->sign ( "$header.$json" ));
    $req->content (
      $self->{acme}{jws_json}->encode (
        { 
          header => { 
            alg => 'RS256', 
            jwk => $self->{acme}{jwk} 
          }, 
          protected => $header, 
          payload => $json, 
          signature => $sig 
        }
      )
    );
    
  }
}

sub _hook_post_request {
  my $self = shift;
  my ( $res ) = @_;

  # Get a new replay nonce.
  if ( my $replay_nonce = $res->header ( 'Replay-Nonce' )) {
    $Net::REST::ACME::replay_nonce = $replay_nonce;
  }

  # Update any links.
  if ( my @links = $res->header ( 'Link' )) {  
  
    foreach my $l ( @links ) {
      next unless ( $l && $l =~ /^<([^>]+)>;rel="([^"]+)"$/i );
      $self->{links}{$2} = $1;
    }
  }
}

sub _hook_post_parse {
  my $self = shift;
  my ( $content, $res ) = @_;

  if ( $res->header ( 'Content-Type' ) eq 'application/problem+json' ) {
    $self->{global_state}{error} = Net::REST::Error->new ( $content );
    $_[0] = undef;
  } elsif ( $res->header ( 'Content-Type' ) eq 'application/pkix-cert' ) {
    $_[0] = { certificate => $_[0] };
  }
  
  if ( my $object_url = $res->header ( 'Location' )) {
    # We got an object returned.
    $_[0] = Net::REST::ACME::Object->new ( $self, $object_url, $_[0] );
  } elsif ( ref $_[0] ) {
    # Maybe objects in the output?
    $self->_find_objects ( $_[0] );
  } 
}

sub links {
  shift->{links} || {};
}

sub fingerprint { 
  shift->{acme}{fingerprint} 
}

package Net::REST::ACME::Object;

use strict;
use warnings;

use base 'Net::REST::ACME';

our $AUTOLOAD;

sub new {
  my $class = shift;
  my ( $acme, $uri, $data ) = @_;
  
  # Start as a shallow copy from the ACME client with the object URI as the
  # new route.
  my $self = $acme->route ( $uri );
  bless $self, $class;

  # Any object data is contained in the object.  
  $self->{acme_object} = {
    uri => $uri,
  };

  # We need a bit of a weird heuristic to determine the type of this object.
  my @p = ( reverse split '/', $uri );
  $self->{acme_object}{type} = $p[1];	# a reasonable guess
  foreach my $p ( reverse ( split '/', $uri )) {
    if ( 
      grep { $p eq $_ } qw( 
        directory new-nonce new-reg reg new-authz new-app app authz challenge 
        cert cert-chain revoke-cert new-cert key-change 
      )
    ) {
      $self->{acme_object}{type} = $p;
      last;
    }
  }
  
  # Is the data already present?
  if ( $data ) {
    $self->{acme_object}{data} = $data;
    $self->_find_contained_objects;
  }
  
  return $self;
  
}

sub uri {
  shift->{acme_object}{uri};
}

sub attr {
  my $self = shift;

  unless ( defined $self->{acme_object}{data} ) {
    # Data not yet cached. Retrieve it.
    if ( $self->{acme_object} =~ /^new-/ ) {
      $self->{acme_object}{data} = $self->SUPER::post( resource => $self->{acme_object}{type} );
    } else {
      $self->{acme_object}{data} = $self->SUPER::get ( $self->{acme_object}{uri} );
    }
    $self->_find_contained_objects;
  }
  
  if ( @_ ) {
    my ( $attr ) = @_;
    if ( exists $self->{acme_object}{data}{$attr} ) {
      return $self->{acme_object}{data}{$attr};
    } else {
      $attr =~ s/_/-/g;
      return $self->{acme_object}{data}{$attr} || undef;
    }
  } else {
    return $self->{acme_object}{data};
  }
}

sub update {
  my $self = shift;
  my %mod = @_;
  
  $self->{acme_object}{data} = $self->SUPER::post (
    resource => $self->{acme_object}{type},
    %mod
  );
  
}

sub _find_contained_objects {
  my $self = shift;
  if ( $self->{acme_object}{data} ) {
    foreach my $v ( values %{$self->{acme_object}{data} || {}} ) {
      $self->_find_objects ( $v ) if ( ref $v );
    }
  }
}


1;

package Net::REST;

# TODO: Some kind of session support.

use strict;
use warnings;

use Carp;
use HTTP::Cookies;
use LWP::UserAgent;
use HTTP::Response;
use HTTP::Request;
use MIME::Base64;
use Net::REST::Error;
use Time::HiRes;

our $AUTOLOAD;

sub new {

  my $class = shift;
  my %param = @_;
  
  my $self = bless {}, $class;
  $self->_init ( %param );
  
  # Determine the base URL.
  if ( $self->{route} = $param{base_url} ? $param{base_url} : $self->{config}{default_base_url} ) {

    # Should we force the base URL to end with a slash?
    if ( my $e = $self->{config}{base_url_ends_with} ) {
      $self->{route} .= $e unless ( $self->{route} =~ m{$e$} );
    }
    
    # Determine the content type to be used for requests.
    if ( my $ct = $self->{config}{request}{content_type} ) {
      $self->{content_type} = $ct;
    }

    # Headers and arguments which are to be sent on every request are
    # collected here.
    $self->{default_headers} ||= {};
    $self->{default_arguments} ||= {};
  
    # Do we use API keys for this interface?
    if ( my $c = $self->{config}{api_key} ) {		
      if ( $param{api_key} ) {
      
        # Apply any formatting to the API key.
        my $api_key = $c->{format} ? sprintf ( $c->{format}, $param{api_key} ) : $param{api_key};
      
        # How should we include the API key?
        if ( $c->{include_as} eq 'argument' ) {
          $self->{default_arguments}{$c->{name} || 'key'} = $api_key;
        } elsif ( $c->{include_as} eq 'header' ) {
          $self->{default_headers}{$c->{name} || 'X-API-Key'} = $api_key;
        }
        
      } else { croak "Required parameter api_key not specified" }
    } elsif ( $self->{config}{http_basic_authentication} and $param{username} ) {
    
      # HTTP Basic authentication
      $self->{default_headers}{'Authorization'} = join ( ' ',
        'Basic',
        MIME::Base64::encode_base64 ( 
          join ( ':', $param{username}, $param{password} ),
          ''
        )
      );
    }
    
    # Initialise a user agent for doing requests.
    $self->{ua} = LWP::UserAgent->new (
      %{ $param{useragent} || {} },
      cookie_jar => HTTP::Cookies->new
    );
  
  } else { croak "Required parameter base_url not specified" }

  $self->{debug} = 1 if ( $param{debug} );
  $self->{autothrottle} = $param{autothrottle};
  $self->{global_state} = {};

  return $self;
  
}

sub _init { croak "Attempt to use main class instead of proper subclass" }

sub _set {
  my $self = shift;
  my %param = @_;
  while ( my ( $k, $v ) = each %param ) {
    $self->{config}{$k} = $v;
  }
}

sub error { shift->{global_state}{error} }

sub execute {
  my $self = shift;
  my $http_method = uc ( shift );
  my $method = shift;
  my $param = $self->_process_parameters ( @_ );
  
  if (( ! $param ) || ( ref $param eq 'HASH' )) {
    while ( my ( $key, $value ) = each %{$self->{default_arguments} || {}} ) {
      $param->{$key} = $value unless ( exists $param->{$key} );
    }
  }

  $self->_hook_pre_execute ( $http_method, $method, $param );  

  my $uri = URI->new ( $self->{route} );
  my $req = HTTP::Request->new ( $http_method => $uri );

  # Add default headers (such as an API key)
  $req->headers->header ( %{$self->{default_headers}} ) if ( %{$self->{default_headers}} );

  $self->_hook_pre_serialisation ( $req, $method, $param );

  # If arguments are given, serialise and add to request.
  $param = undef if (( ref $param eq 'HASH' ) && ( ! %{$param} ));
  if ( $param ) {  
    if (( my $s = $self->{config}{request}{serializer} ) && ( $http_method ne 'GET' )) {
    
      # Serialize parameters in the request body.
      my ( $content_type, $content_body ) = $s->serialize ( $method, $param );
      $req->content ( $content_body );
      $req->headers->header ( 'Content-Type' => $self->{config}{request}{content_type} || $content_type );

    } elsif (( ref $param eq 'HASH' ) || ( ref $param eq 'ARRAY' )) {
    
      if ( $self->{config}{get_with_query_string} ) {
      
        # Serialize the parameters and add them to the query string.
        my ( $content_type, $content_body ) = $s->serialize ( $method, $param );
        $uri->query ( $content_body );
      
      } else {
    
        # Add parameters to the URL.
        $uri->query_form ( $param );
        
      }
      
      $req->uri ( $uri );
      
    }
  }
  
  $self->_hook_pre_request ( $req );
  
  if ( $self->{debug} ) {
    print STDERR $req->dump ( prefix => "$self >>> ", maxlength => 10240, no_content => '' );
    print STDERR "$self ---\n";
  }
  
  # If we autothrottle requests, this is the moment to wait a bit.
  if ( my $throttle = $self->{autothrottle} ) {
    if ( my $previous = $self->{global_state}{last_request} ) {
      my $elapsed = Time::HiRes::time - $previous;
      if ( $elapsed < $throttle ) {
        Time::HiRes::sleep ( $throttle - $elapsed );
      }
    }
    $self->{global_state}{last_request} = Time::HiRes::time;
  }

  # Now we execute the request.
  $self->{global_state}{error} = undef;
  if ( my $response = $self->{ua}->request ( $req )) {
  
    $self->_hook_post_request ( $response );

    my $resp_content = $response->decoded_content;

    if ( $self->{debug} ) {
      print STDERR $response->dump ( prefix => "$self <<< ", maxlength => 10240, no_content => '' );
    }
  
    # Regardless of the status, we try to parse whatever content we got. 
    # This is because some REST interfaces will return a HTTP error status
    # along with informational content serialised in whatever format they
    # support.
    
    if ( length ( $resp_content ) && ( my $p = $self->{config}{response}{parser} )) {

      $self->_hook_pre_parse ( $resp_content, $response );
      $resp_content = $p->parse ( $method, $response->header ( 'Content-Type' ), $resp_content );
      $self->_hook_post_parse ( $resp_content, $response );
      
      if ( defined $resp_content ) {
        my $error;
        # If path_as_error defines a specific kind of path, try to traverse it.
        if ( my $p = $self->{config}{response}{path_as_error} ) {
          $error = $resp_content;
          foreach ( split '/', $p ) {
            next unless ( $_ );
            if (( ref $error eq 'HASH' ) && exists $error->{$_} ) {
              $error = $error->{$_};
            } else {
              $error = undef;
              last;
            }
          }
        }
        
        $error ||= $self->_get_error ( $resp_content );
        $self->{global_state}{error} = Net::REST::Error->new ( $error ) if ( defined $error );
        
      }  
    }

    # If the HTTP status indicates an error we set it as the error.
    if ( $response->is_error && ( ! $self->{global_state}{error} )) {
      $self->{global_state}{error} = Net::REST::Error->new ( $response );
    }
    
    if ( $self->{global_state}{error} ) {
      $self->_hook_post_request_error ( $self->{global_state}{error} );
    }
    
    my $value = $self->_get_value ( $resp_content );
    $self->_hook_post_execute ( $http_method, $method, $param, $value );
    
    return $value;
    
  } else { croak "An internal error occurred while processing the request: no value returned by LWP::UserAgent->request" }
}

sub route {
  my $self = shift;
  my @routes = @_;
  
  if ( @routes ) {

    # Create a copy of ourselves with the new route(s) added to the URL.
    # Just a shallow copy works fine.
    my $clone = { %{$self} };
    bless $clone, ref $self;
    if ( $routes[0] =~ m{^https?://}i ) {	# not a relative path
      $clone->{route} = shift @routes;
    } elsif ( $clone->{route} !~ m{/$} ) {	# add a backslash
      $clone->{route} .= '/';
    }
    $clone->{route} .= join ( '/', @routes );
    return $clone;
  
  }
  
  return $self;
  
}

# Hooks to be overridden by specific sub classes.
sub _hook_pre_execute {}
sub _hook_pre_serialisation {}
sub _hook_pre_request {}
sub _hook_post_request {}
sub _hook_pre_parse {}
sub _hook_post_parse {}
sub _hook_post_request_error {}
sub _hook_post_execute {}

# And these ones can be overridden as well.
sub _get_error {}
sub _get_value { $_[0]->{global_state}{error} ? undef : $_[1] }
sub _process_parameters { shift; return { @_ }; }

sub AUTOLOAD {
  my $self = shift;
  my $method = $AUTOLOAD;
  $method =~ s/.*:://;
  
  croak "Internal error; illegal autoloaded method name $method" if ( $method =~ /^_/ );
  
  if ( my $m = $self->{config}{request}{methods}{$method} || $self->{config}{request}{methods}{'*'} ) {
  
    # Matches one of the defined methods; do whatever is configured.
    if ( $m->{route} && ( my @r = ( ref $m->{route} ? @{$m->{route}} : $m->{route} ))) {
    
      foreach ( @r ) {
      
        s{&}{$method}ge;			# Process the '&' marker which references the method name.
        s{\*}{join ( '/', @_ ) || ''}ge;	# Process the '*' marker which adds all arguments as route elements.
        my $highest_ref = -1;
        while ( m{#([0-9]+)} ) {		# Process the '#0' - '#999' style markers which reference a specific argument.
          my $nr = $1;
          $highest_ref = $nr if ( $nr > $highest_ref );
          s{#$nr}{$_[$nr] || ''}ge;
        }
        if ( m{#\*} ) {				# Process the '#*' marker which takes all remaining arguments.
          s{#\*}{join ( '/', @_[($highest_ref + 1)..$#_] ) || ''}ge;
        } elsif ( $highest_ref >= 0 ) {		# Shift arguments rom the @_ array if necessary (we won't need them anymore and they should not be passed as arguments).
          @_ = @_[( $highest_ref + 1 )..$#_];
        }
      
      }
      
      my $new_route = join ( '/', map { $_ || () } @r );
      if ( length ( $new_route )) {
        $self = $self->route ( $new_route );
      }
    }
    
    if ( $m->{http} ) {    
      # Execute a HTTP method.
      return $self->execute ( $m->{http}, $method, $m->{pass_arguments} ? @_ : ());
    }
    
  } else { croak "Undefined method $self->$method called" }

  return $self;

}

# Empty stub to prevent the autoloader from being called.
sub DESTROY { }

1;

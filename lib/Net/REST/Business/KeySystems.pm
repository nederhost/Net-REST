package Net::REST::Business::KeySystems;

use strict;
use warnings;

use base 'Net::REST';
use Carp;

sub _init {
  my $self = shift;
  my %param = @_;
  
  unless ( $param{username} && $param{password} ) {
    croak "Required parameters username and/or password not specified";
  }
  
  my $codec = Net::REST::Business::KeySystems::Codec->new ( 
    username => $param{username}, 
    password => $param{password} 
  );
  
  $self->_set (
    default_base_url => 'https://ssl.rrpproxy.net/api/call.cgi',    
    request => {
      serializer => $codec,
      methods => {
        '*' 		=> { http => 'post' },
      }
    },
    
    response => { 
      parser => $codec,
    },

  );
}

sub _get_error {
  my $self = shift;
  my ( $r ) = @_;
  
  if ( $r->{code} && ( $r->{code} > 299 )) {
    return {
      code => $r->{code},
      message => $r->{description},
    };
  } else { return undef }
}

package Net::REST::Business::KeySystems::Codec;

use strict;
use warnings;

use base 'Net::REST::Codec::Form';
use Carp;

sub new {
  my $class = shift;
  my %param = @_;
  my $self = $class->SUPER::new ( @_ );
  $self->{keysystems} = {
    username => $param{username},
    password => $param{password}
  };
  return $self;
}

sub parse {
  my $self = shift;
  my ( $method, $content_type, $data ) = @_;
  
  my $r = {};  
  if ( $data =~ /^\s*\[RESPONSE\]\n(.+)/s ) {
    foreach my $l ( split /\n/, $1 ) {
      if ( $l =~ /^\s*([^\s=]+)\s*=\s*(.*)/ ) {
        my ( $f, $v ) = ( $1, $2 );
        $f = lc ( $f );
        if ( $f =~ /^property\[([^\]]+)\]\[([0-9]+)\]/ ) {
          $r->{property}{$1}[$2] = $v;
        } else {
          $r->{$f} = $v;
        }
      } elsif ( $l eq 'EOF' ) {
        last;
      } else {
        carp "Line cannot be parsed: $l";
      }
    }
  }

  return $r;
  
}

sub serialize {
  my $self = shift;
  my ( $method, $param ) = @_;
 
  # KeySystems-specific serialisation of a request.
  
  my $cmd = "[COMMAND]\nCOMMAND=" . $method . "\n";
  while ( my ( $k, $v ) = each %{$param} ) {
    if ( ref $v eq 'ARRAY' ) {
      for ( my $i = 0; $i <= $#{$v}; $i++ ) {
        $cmd .= uc ( $k ) . $i . '=' . $v->[$i] . "\n";
      }
    } else {
      $cmd .= uc ( $k ) . '=' . $v . "\n";
    }
  }

  # Then the whole thing is actually serialised a second time as a URL
  # encoded form.
  return $self->SUPER::serialize (
    $method,
    {
      s_login => $self->{keysystems}{username},
      s_pw => $self->{keysystems}{password},
      s_command => $cmd
    }
  );
}

1;

package Net::REST::Error;

use strict;
use warnings;

use overload 
  '""' => 'as_string';

sub new {
  my $class = shift;
  my $obj = shift;
  my $self = bless {}, $class;
  
  if ( eval { $obj->isa ( 'HTTP::Response' ) } ) {
    $self->{type} = 'http';
    $self->{code} = $obj->code;
    $self->{message} = $obj->message;
    $self->{error} = {
      content => $obj->decoded_content
    };
  } else {
    $self->{type} = 'request';
    $self->{error} = $obj;
    if ( ref $obj eq 'HASH' ) {
      foreach ( 'errorcode', 'errorno', 'errno', 'err', 'code', 'error' ) {
        if ( exists $obj->{$_} ) {
          $self->{code} = $obj->{$_};
          last;
        }
      }
      foreach ( 'errormessage', 'errormsg', 'errmsg', 'message', 'error' ) {
        if ( exists $obj->{$_} ) {
          $self->{message} = $obj->{$_};
          last;
        }
      }
    }
  }
  
  $self;
}

sub code { shift->{code} || 0 }
sub message { shift->{message} || 'unknown error' }
sub type { shift->{type} }

sub as_string {
  my $self = shift;
  sprintf ( '[%s error %s: %s]', $self->type, $self->code, $self->message );
}

1;

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
    $self->{headers} = {
      map {
        $_ => $obj->header ( $_ )
      } ( $obj->header_field_names )
    };
  } else {
    $self->{type} = 'request';
    $self->{error} = $obj;
    if ( ref $obj eq 'HASH' ) {
      foreach my $k ( %{$obj} ) {
        foreach ( 'errorcode', 'errorno', 'errno', 'err', 'code', 'error', 'status' ) {
          if ( lc ( $k ) eq $_ ) {
            $self->{code} = $obj->{$k};
            last;
          }
        }
        foreach ( 'errormessage', 'errormsg', 'errmsg', 'message', 'error', 'detail' ) {
          if ( lc ( $k ) eq $_ ) {
            $self->{message} = $obj->{$k};
            last;
          }
        }
      }
    }
  }
  
  $self;
}

sub code { shift->{code} || 0 }
sub headers { shift->{headers} || {} }
sub message { shift->{message} || 'unknown error' }
sub type { shift->{type} }

sub as_string {
  my $self = shift;
  sprintf ( '[%s error %s: %s]', $self->type, $self->code, $self->message );
}

1;

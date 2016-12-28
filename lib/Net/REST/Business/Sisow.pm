package Net::REST::Business::Sisow;

use strict;
use warnings;

use base 'Net::REST';
use Carp;
use Digest::SHA1;
use Net::REST::Codec::XML;
use URI::Encode;

sub _init {
  my $self = shift;
  
  my %param = @_;
  if ( $param{merchantid} && $param{merchantkey} ) {
    $self->{sisow} = {
      merchantid => $param{merchantid},
      merchantkey => $param{merchantkey}
    };
    $self->{sisow}{shopid} = $param{shopid} if ( $param{shopid} );
  } else {
    croak "Required parameters merchantid and merchantkey not specified";
  }
  
  $self->_set (
    default_base_url => 'https://www.sisow.nl/Sisow/iDEAL/RestHandler.ashx/',
    base_url_ends_with => '/',
    request => {
      methods => {
        '*' 		=> { http => 'get', route => ['&'] },
      }
    },
    response => { 
      parser => Net::REST::Codec::XML->new,
      path_as_error => '/errorresponse/error'
    },

  );
}

#
# The _hook_pre_execute adds the required merchantid and shopid parameters
# to all requests and calculates the sha1 parameter for those requests that
# require it.
#

sub _hook_pre_execute {
  my $self = shift;
  my ( $httpd_method, $method, $param ) = @_;

  print $self->{route};
  
  my $hash_source;
  if ( $self->{route} =~ m{/TransactionRequest/?$} ) {
    $hash_source = [ 'purchaseid', 'entrancecode', 'amount', 'shopid' ];
  } elsif ( $self->{route} =~ m{/StatusRequest/?$} ) {
    $hash_source = [ 'trxid', 'shopid' ];
  } elsif ( $self->{route} =~ m{/CheckMerchantRequest/?$} ) {
    $hash_source = [];
  } elsif ( $self->{route} =~ m{/(CancelReservation|CreditInvoice|Invoice|Refund)Request/?$} ) {
    $hash_source = [ 'trxid' ];
  } elsif ( $self->{route} =~ m{/BatchRequest/?$} ) {
    $hash_source = [ 'batchid', 'shopid' ];
  }
  
  foreach ( 'shopid', 'merchantid' ) {
    if ( exists $self->{sisow}{$_} ) {
      $param->{$_} = $self->{sisow}{$_};
      push @{$hash_source}, $_ if ( defined $hash_source );
    }
  }
  
  if ( defined $hash_source ) {

    warn "SHA1: ". join ( ',',
      ( map { defined $param->{$_} ? $param->{$_} : '' } @{$hash_source} ),
      $self->{sisow}{merchantkey}
    );

    $param->{sha1} = Digest::SHA1::sha1_hex (
      ( map { defined $param->{$_} ? $param->{$_} : '' } @{$hash_source} ),
      $self->{sisow}{merchantkey}
    );
  }  
 
  # We need these in some cases to check the SHA1 of the response 
  $self->{sisow}{last_param} = $param;
  
}

#
# The _hook_post_parse checks the SHA1 signature of the response that is
# calculated by Sisow.
#

sub _hook_post_parse {
  my $self = shift;
  my ( $r ) = @_;
  
  croak "Parse error" unless ( ref $r eq 'HASH' );
  
  # Determine the topmost tag.
  my ( $top ) = ( keys %{$r} );
  return unless $r->{$top}{signature};
  
  if ( my $sha1 = $r->{$top}{signature}{sha1} ) {
  
    if ( $top =~ /^(.+)(response|request)$/ ) {
      my ( $request, $type ) = $1;
  
      # Signed response. The fields over which the signature is calculated
      # different per type of request.
      if (
        my $hash_source = {
          'transaction' => { f => ['trxid', 'issuerurl', 'invoiceno', 'documentid' ] },
          'status' => { f => ['trxid', 'status', 'amount', 'purchaseid', 'entrancecode', 'consumeraccount'], t => 'transaction' },
          'invoice' => { f => ['invoiceno', 'documentid' ] },
          'cancelreservation' => { f => ['trxid'], t => 'reservation' },
          'creditinvoice' => { f => ['invoiceno', 'documentid' ] },
          'refund' => { f => ['refundid'] },
          'checkmerchant' => { f => [], t => 'merchant' },
          'batch' => { f => [ 'batchid', 'count', 'payed' ] }
        }->{$request}
      ) {
        my $t = $hash_source->{t} || $request;
        if ( 
          Digest::SHA1::sha1_hex (
            map {
              if ( defined $r->{$top}{$t}{$_} ) {
                $r->{$top}{$t}{$_};
              } elsif ( defined $self->{sisow}{last_param}{$_} ) {
                $self->{sisow}{last_param}{$_};
              } elsif ( defined $self->{sisow}{$_} ) {
                $self->{sisow}{$_};
              } else {
                '';
              }
            } (
              @{$hash_source->{f}},
              'merchantid',
              'merchantkey'
            )
          ) eq $sha1
        ) {
          warn "Hash checked: $sha1";
        } else {
          croak "Invalid sha1 hash in response";
        }
        
        # Decode any ...url fields (they are provided in URL-encoded form by the Sisow API).
        while ( my ( $f, $v ) = each %{$r->{$top}{$t}} ) {
          if (( $f =~ /url$/ ) && ( $v =~ /^https?/ )) {
            $r->{$top}{$t}{$f} = URI::Encode::uri_decode ( $v );
          }
        }
      }
    }
    
    
  }
}

=head1 NAME

Net::REST::Businesses::Sisow - Implementation of the Sisow API.

=head1 DESCRIPTION

This module implements the Sisow 1.0.0 API for payment transactions and
ebilling as described on https://www.sisow.nl/downloads/REST321.pdf

=head1 SYNOPSIS

 # The initialisation values are to be provided by Sisow; merchantid and
 # merchantkey are required, shopid is optional.
 
 $api = Net::REST::Business::Sisow->new (
   merchantid => '1234567',
   merchantkey => 'ab8cb728d8787857fcba0989',
   shopid => '1'
 );

The API handle can be used to do a request, like this:
 
 my $directory = $api->DirectoryRequest;
 
Now $directory contains:

 {
   'directoryresponse' => {
     '-version' => '1.0.0',
     '-xmlns' => 'https://www.sisow.nl/Sisow/REST',
     'directory' => {
       'issuer' => [
         {
           'issuername' => 'ABN Amro Bank',
           'issuerid' => '01'
         },
         {
           'issuername' => 'ASN Bank',
           'issuerid' => '02'
         },
         # ... etcetera etcetera ...
       ]
     }
   }
 }

Starting a transaction:

 my $transaction = $api->TransactionRequest (
   payment => 'ideal',
   purchaseid => '234567890',
   entrancecode => '12345678',
   amount => 1000,      # in cents, so this is EUR 10.00!
   description => 'Description of this payment',
   returnurl => 'https://www.example.com/'
 );
 
Now $transaction contains:

 {
   'transactionrequest' => {
     '-version' => '1.0.0',
     '-xmlns' => 'https://www.sisow.nl/Sisow/REST',
     'transaction' => {
       'issuerurl' => 'https://www.sisow.nl/Sisow/iDeal/RestPay.aspx?id=80515969343&merchantid=2537404380&sha1=20def7c835963b035b1cb120113bc3d4a1119b88',
       'trxid' => ''
     },
     'signature' => {
       'sha1' => '23c249224ba08ee8505a628b39b139f6b51d5832'
     }
   }
 }

Note that SHA1 signatures are checked by the API, you do not usually need to
do this yourself. Any field that is returned by the Sisow API with a name
that ends on url is assumed to be an URL-encoded URL which is automatically
decoded.

=cut

1;

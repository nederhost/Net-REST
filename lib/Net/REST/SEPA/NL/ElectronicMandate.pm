package Net::REST::SEPA::NL::ElectronicMandate;

use strict;
use warnings;

use base 'Net::REST';
use Carp;
# use Net::REST::SEPA::NL::ElectronicMandate::XML;

sub _init {
  my $self = shift;
  
  my %param = @_;
  if ( $param{merchant_id} && $param{key} && $param{key_id} && $param{routing_url} ) {
    $self->{emandate} = {
      merchant_id => $param{merchant_id},
      sub_id => $param{sub_id} || 0,
      key => $param{key},
      key_id => $param{key_id},
      routing_url => $param{routing_url}
    };
  } else {
    croak "Required parameters merchant_id, key and/or routing_url not specified";
  }
  
  $self->_set (
    default_base_url => $self->{emandate}{routing_url},
    request => {
      serializer => Net::REST::SEPA::NL::ElectronicMandate::XML->new ( %{$self->{emandate}} ),
      methods => {
        '*' => { http => 'post', pass_arguments => 1 },
      }
    },
    response => {
      parser => Net::REST::SEPA::NL::ElectronicMandate::XML->new ( %{$self->{emandate}} ),
      path_as_error => '/AcquirerErrorRes/Error'
    },

  );
}

package Net::REST::SEPA::NL::ElectronicMandate::XML;

use strict;
use warnings;

use base 'Net::REST::Codec::XML';

use Carp;
use Crypt::OpenSSL::RSA;
use Digest::SHA;
use MIME::Base64;
use XML::CanonicalizeXML;
use XML::Writer;

sub new {
  my $class = shift;
  bless { @_ }, $class;
}

sub parse {
  my $self = shift;
  my ( $method, $content_type, $xml ) = @_;
  my $response = $self->SUPER::parse ( @_ );
  
  # The default XML::Fast parser is pretty nice, but we do some additional
  # work to fetch the most useful data from the response and put it in a
  # seperate hash key.
  
  if ( $response->{DirectoryRes} ) {
  
    # Always return a reference to a list.
    $response->{directory} = [ 
      ( ref $response->{DirectoryRes}{Directory}{Country} eq 'ARRAY' ) 
      ? @{$response->{DirectoryRes}{Directory}{Country}} 
      : $response->{DirectoryRes}{Directory}{Country} 
    ];
    
  } elsif ( $response->{AcquirerTrxRes} ) {
  
    $response->{transaction} = {
      acquirer_id => $response->{AcquirerTrxRes}{Acquirer}{acquirerID},
      transaction_id => $response->{AcquirerTrxRes}{Transaction}{transactionID},
      auth_url => $response->{AcquirerTrxRes}{Issuer}{issuerAuthenticationURL}
    };

  } elsif ( $response->{AcquirerStatusRes} ) {
  
    # Save the full original XML so we can always validate the signature
    # (necessary if the status response contains a signed mandate).
    $response->{status}{full_xml} = $xml;

    # Make sure the status code is easily available.    
    $response->{status}{code} = lc ( $response->{AcquirerStatusRes}{Transaction}{status} );
    
    # We need some information from the PAIN.012 message (the actual
    # mandate), if present.
    if ( $response->{status}{code} eq 'success' ) {
      if ( my $c = $response->{AcquirerStatusRes}{Transaction}{container} ) {
    
        if ( ref $c eq 'HASH' ) {

          # Quick and dirty way to find the namespace prefix they used from
          # the XML-based hash we get from XML::Fast.
          my $prefix;
          foreach ( keys %{$c} ) {
            if ( m/^(([^:]*):)?Document$/ ) {
              $prefix = $1;
              last;
            }
          }
    
          # The double OrgnlMndt tag is NOT a bug.
          if ( my $mandate = $c->{$prefix . 'Document'}{$prefix . 'MndtAccptncRpt'}{$prefix . 'UndrlygAccptncDtls'}{$prefix . 'OrgnlMndt'}{$prefix . 'OrgnlMndt'} ) {
            $response->{status}{debtor} = {
              name => $mandate->{$prefix . 'Dbtr'}{$prefix . 'Nm'},
              iban => $mandate->{$prefix . 'DbtrAcct'}{$prefix . 'Id'}{$prefix . 'IBAN'},
              bic => $mandate->{$prefix . 'DbtrAgt'}{$prefix . 'FinInstnId'}{$prefix . 'BICFI'},
            };
            if ( my $debtor_reference = $mandate->{$prefix . 'Dbtr'}{$prefix . 'Id'}{$prefix . 'PrvtdId'}{$prefix . 'Othr'}{$prefix . 'Id'} ) {
              $response->{status}{debtor}{debtor_reference} = $debtor_reference;
            }
            if ( my $ultimate_debtor = $mandate->{$prefix . 'UltmtDbtr'}{$prefix . 'Nm'} ) {
              $response->{status}{debtor}{ultimate_debtor} = $ultimate_debtor;
            }
            $response->{status}{creditor} = {
              name => $mandate->{$prefix . 'Cdtr'}{$prefix . 'Nm'},
              creditor_id => $mandate->{$prefix . 'CdtrSchmeId'}{$prefix . 'Id'}{$prefix . 'PrvtId'}{$prefix . 'Othr'}{$prefix . 'Id'}
            };
            $response->{status}{mandate} = {
              mandate_id => $mandate->{$prefix . 'MndtId'}
            };
          }
          
          if ( my $validation_reference = $c->{$prefix . 'Document'}{$prefix . 'MndtAccptncRpt'}{$prefix . 'GrpHdr'}{$prefix . 'Authstn'}{$prefix . 'Prtry'} ) {
            $response->{status}{mandate}{validation_reference} = $validation_reference;
          }
        }    
      }
    }
  }
  
  return $response;
}

sub serialize {
  my $self = shift;
  my ( $method, $param ) = @_;
  
  my $x = XML::Writer->new ( 
    OUTPUT => 'self',
    UNSAFE => 1,
    NAMESPACES => 1,
    PREFIX_MAP => {
      'http://www.betaalvereniging.nl/iDx/messages/Merchant-Acquirer/1.0.0' => '',
      'http://www.w3.org/2000/09/xmldsig#' => 'ds',
      'http://www.w3.org/2001/XMLSchema-instance' => 'xsi'
    },
    ENCODING => 'utf-8',
    FORCED_NS_DECLS => [
      'http://www.betaalvereniging.nl/iDx/messages/Merchant-Acquirer/1.0.0',
      'http://www.w3.org/2000/09/xmldsig#',
      'http://www.w3.org/2001/XMLSchema-instance'    
    ]
  );
  
  $x->xmlDecl ( 'UTF-8' );
  $x->startTag ( $method . 'Req',
    'version' => '1.0.0',
    'productID' => 'NL:BVN:eMandatesCore:1.0'
  );

  my @now = gmtime;
  my $timestamp = sprintf ( '%04d-%02d-%02dT%02d:%02d:%02d.000Z', $now[5] + 1900, $now[4] + 1, $now[3], $now[2], $now[1], $now[0] );
  $x->dataElement ( 'createDateTimestamp', $timestamp );
  
  if ( $method eq 'Directory' ) {
  
    $x->startTag ( 'Merchant' );
    $x->dataElement ( 'merchantID', $self->{merchant_id} );
    $x->dataElement ( 'subID', $self->{sub_id} );
    $x->endTag ( 'Merchant' );
  
  } elsif ( $method eq 'AcquirerTrx' ) {
 
    $param->{sequence_type} ||= 'RCUR';	# or OOFF 
    $param->{language} ||= 'nl';
    $param->{expiration_period} ||= '';	# Should usually be left empty according to documentation
    $param->{reason} ||= '';

    $param->{debtor_reference} ||= '';
  
    foreach ( 'return_url', 'entrance_code', 'mandate_id', 'sequence_type', 'issuer_id' ) {
      confess "Required parameter $_ not specified" unless ( $param->{$_} );
    }

    $x->startTag ( 'Issuer' );
    $x->dataElement ( 'issuerID', $param->{issuer_id} );
    $x->endTag ( 'Issuer' );
    
    $x->startTag ( 'Merchant' );
    $x->dataElement ( 'merchantID', $self->{merchant_id} );
    $x->dataElement ( 'subID', $self->{sub_id} );    
    $x->dataElement ( 'merchantReturnURL', $param->{return_url} );
    $x->endTag ( 'Merchant' );
    
    $x->startTag ( 'Transaction' );
    $x->dataElement ( 'expirationPeriod', $param->{expiration_period} ) if ( $param->{expiration_period} );
    $x->dataElement ( 'language', $param->{language} );
    $x->dataElement ( 'entranceCode', $param->{entrance_code} );
    $x->startTag ( 'container' );
    
    # The actual PAIN.009 message is in here.
    $x->raw ( '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.009.001.04" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' );
    $x->startTag ( 'MndtInitnReq' );
    $x->startTag ( 'GrpHdr' );
    $x->dataElement ( 'MsgId', sprintf ( '%s-%s-%s', $param->{mandate_id}, 'req', time ));
    $x->dataElement ( 'CreDtTm', $timestamp );
    $x->endTag ( 'GrpHdr' );
    $x->startTag ( 'Mndt' );
    $x->dataElement ( 'MndtId', $param->{mandate_id} );
    $x->dataElement ( 'MndtReqId', 'NOTPROVIDED' );						# required to be this
    $x->raw ( '<Tp><SvcLvl><Cd>SEPA</Cd></SvcLvl><LclInstrm><Cd>CORE</Cd></LclInstrm></Tp>' );	# required boilerplate
    $x->startTag ( 'Ocrncs' );
    $x->dataElement ( 'SeqTp', $param->{sequence_type} );
    $x->endTag ( 'Ocrncs' );
    
    if ( $param->{reason} ) {
      $x->startTag ( 'Rsn' );
      $x->dataElement ( 'Prtry', $param->{reason} );
      $x->endTag ( 'Rsn' );
    }
    
    $x->emptyTag ( 'Cdtr' );									# will be filled by issuer
    $x->startTag ( 'Dbtr' );
    
    if ( $param->{debtor_reference} ) {
      $x->startTag ( 'Id' );
      $x->startTag ( 'PrvtId' );
      $x->startTag ( 'Othr' );
      $x->dataElement ( 'Id', $param->{debtor_reference} );
      $x->endTag ( 'Othr' );
      $x->endTag ( 'PrvtId' );
      $x->endTag ( 'Id' );
    }
     
    $x->endTag ( 'Dbtr' );
    $x->startTag ( 'DbtrAgt' );
    $x->startTag ( 'FinInstnId' );
    $x->dataElement ( 'BICFI', $param->{issuer_id} );
    $x->endTag ( 'FinInstnId' );
    $x->endTag ( 'DbtrAgt' );
    $x->endTag ( 'Mndt' );
    $x->endTag ( 'MndtInitnReq' );
    $x->raw ( '</Document>' );
    # End of PAIN.009 message 
   
    $x->endTag ( 'container' );
    $x->endTag ( 'Transaction' );
  
  } elsif ( $method eq 'AcquirerStatus' ) {

    unless ( $param->{transaction_id} ) {
      confess "Required parameter transaction_id not specified";
    }

    $x->startTag ( 'Merchant' );
    $x->dataElement ( 'merchantID', $self->{merchant_id} );
    $x->dataElement ( 'subID', $self->{sub_id} );    
    $x->endTag ( 'Merchant' );
    $x->startTag ( 'Transaction' );
    $x->dataElement ( 'transactionID', $param->{transaction_id} );
    $x->endTag ( 'Transaction' );
  
  } else { confess "Invalid method specified: $method" }
  
  # Finish the XML.
  $x->endTag ( $method . 'Req' );
  my $xml = $x->to_string;

  # Sign the XML. This begins with generating a SHA256 digest over the
  # canonicalized version of the request.
  my $digest = MIME::Base64::encode_base64 ( Digest::SHA::sha256 ( $self->_canon_xml ( $xml )));  
  $digest =~ s/[\s\n]*$//;

  # Now create the SignedInfo element. 
  my $si = XML::Writer->new ( OUTPUT => 'self' );
  $si->startTag ( 'SignedInfo', 'xmlns' => 'http://www.w3.org/2000/09/xmldsig#' );
  $si->emptyTag ( 'CanonicalizationMethod', 'Algorithm' => 'http://www.w3.org/2001/10/xml-exc-c14n#' );
  $si->emptyTag ( 'SignatureMethod', 'Algorithm' => 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256' );
  $si->startTag ( 'Reference', 'URI' => '' );
  $si->startTag ( 'Transforms' );
  $si->emptyTag ( 'Transform', 'Algorithm' => 'http://www.w3.org/2000/09/xmldsig#enveloped-signature' );
  $si->emptyTag ( 'Transform', 'Algorithm' => 'http://www.w3.org/2001/10/xml-exc-c14n#' );
  $si->endTag ( 'Transforms' );
  $si->emptyTag ( 'DigestMethod', 'Algorithm' => 'http://www.w3.org/2001/04/xmlenc#sha256' );
  $si->dataElement ( 'DigestValue', $digest );
  $si->endTag ( 'Reference' );
  $si->endTag ( 'SignedInfo' );
  my $sig_info = $si->to_string;

  # Prepare signing  
  my $rsa = Crypt::OpenSSL::RSA->new_private_key ( $self->{key} );
  $rsa->use_pkcs1_padding;
  $rsa->use_sha256_hash;

  # Create the signature by signing a canonicalized version of the
  # SignedInfo element (we use rsa-sha256).
  my $signature = MIME::Base64::encode_base64 ( $rsa->sign ( $self->_canon_xml ( $sig_info )));
  $signature =~ s/[\n\s]*$//;
  
  # The full signature is now simply concatenated together; this is to
  # preserve whitespace and newlines which cannot be changed without making
  # the signature invalid.
  my $sign_xml = '<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">' . 
                 $sig_info . 
                 '<SignatureValue>' . $signature . '</SignatureValue>' . 
                 '<KeyInfo><KeyName>' . $self->{key_id} . '</KeyName></KeyInfo>' .
                 '</Signature>';

  # Finally insert the signature in the request.
  $xml =~ s|(</${method}Req>)|$sign_xml$1|;

  return ( 'application/xml', $xml );  
}

sub _canon_xml {
  my $self = shift;
  my ( $xml ) = @_;
  return XML::CanonicalizeXML::canonicalize (
    $xml,
    '<XPath>(//. | //@* | //namespace::*)</XPath>',
    '',
    1,
    0
  );
}

=head1 NAME

Net::REST::SEPA::NL::ElectronicMandate - Implementation of Dutch electronic
mandates for SEPA Direct Debit ('Incassomachtigen').

=head1 DESCRIPTION

This module implements the Dutch 'Incassomachtigen' protocol version 1.0.0
according to the documentation provided by Betaalvereniging Nederland.

This module is a 'quick and dirty' implementation which currently does not
verify signatures on responses (instead relying on HTTPS to do its job) and
has only support for creating new mandates.  This module implements a very
limited version of XML Signatures which is sufficient for this protocol
only.

This module supports specifying only a single routing URL, which is probably
sufficient in most cases.

=head1 SYNOPSIS
 
 $e = Net::REST::SEPA::NL::ElectronicMandate->new (
   merchant_id => '1234512345',
   sub_id => '0',
   key_id => '8fb4c61239b3f9fe4d9030075d3c9658f57bc341',
   key => $your_private_key_as_pem
   routing_url => 'https://example.com/RoutingWS/handler/yourbank'
 );
 
 $issuers = $e->Directory;
 
 # ... select an issuer as $issuer_id ...
 
 $transaction = $e->AcquirerTrx (
   return_url => 'https://www.example.com/return/',
   entrance_code => 'ec1234567890',
   mandate_id => 'UNIQUE-ID-123',
   issuer_id => $issuer_id,
 );
 
 # ... redirect the user to $transaction->{transaction}{auth_url} ...

 $status = $e->AcquirerStatus (
   transaction_id => $transaction->{transaction}{transaction_id}
 );

All methods return the XML as parsed through XML::Fast, which means that
they will contain an element for the root element in the response.  In
addition to this, some extra information is added to the result for easier
processing.

=head1 METHODS

=head2 Directory

Retrieve a directory of issuers. Accepts no parameters, the result will
contain a key 'directory' of which the value is a reference to a list like
this:

 [
   {
     'countryNames' => 'Nederland',
     'Issuer' => [
       {
         'issuerID' => 'TESTNL20001',
         'issuerName' => 'TEST NL 20001, status "Success"'
       },
       {
         'issuerID' => 'TESTNL20002',
         'issuerName' => 'TEST NL 20002, status "Open"'
       },
       ...
     ]
   },
   ...
 ]
 
The output shown is from the test system, obviously this would include
actual names of banks and their BICs (which are also used as issuer IDs).

=head2 AcquirerTrx

Start a new transaction for signing a mandate. This method accepts the
following parameters:

=over

=item * return_url (required)

A URL to which the user is to be redirected after completing (or cancelling)
signing the mandate.

=item * entrance_code (required)

A unique and hard to guess entrance code which will be provided to the
return_url as the 'ec' parameter; this is especially important when not
using HTTPS.

=item * mandate_id (required)

The ID of the mandate to be signed. Should be unique for the creditor.

=item * issuer_id (required)

The ID of the bank of the debtor, as selected by the debtor. Is the value of
the 'issuerID' field of the selected bank.

=item * reason

A reason for the direct debit; will be shown to the user.

=item * debtor_reference

An optional debtor reference which will be attached to the mandate.

=item * sequence_type

The type of direct debit that will be executed, either 'RCUR' (recurring) or
'OOFF' (one off).  Defaults to 'RCUR'.

=item * language

The language to be used for the user. Defaults to 'nl'.

=item * expiration_period

An expiration period for the transaction specified as an ISO period
indication.  It is recommended not to specify this.

=back

If the transaction could be started the response will include an element
'transaction' which contains a reference to a hash with the following keys:

=over

=item * acquirer_id

The acquirer ID processing the request.

=item * auth_url

The authentication URL to which the user should be redirected for signing
the request.

=item * transaction_id

The transaction ID associated with this transaction.

=back

=head2 AcquirerStatus

Retrieve the status of a transaction. This method requires one parameter:

=over

=item * transaction_id (required)

The ID of the transaction for which the status is requested.

=back

The result will contain a key 'status' of which the value is a reference to
a hash with the following keys:

=over

=item * full_xml

The full, original XML of the status response. This must be saved if the
status code is 'success' and the status contains a signed mandate.

=item * code

The status code of the transaction, in lowercase. The rest of the keys are
present only if code is 'success'.

=item * debtor

Information about the debtor, as a reference to a hash with the following
keys:

=over

=item * iban

The IBAN of the debtor.

=item * bic

The BIC of the debtor's bank.

=item * name

The name of the debtor as returned by its bank.

=item * ultimate_debtor

If an ultimate debtor name is present, it is contained in this value.

=back

=item * mandate

Information about the mandate which should be present in direct debit
transactions based on this mandate.  A reference to a hash with the
following keys:

=over

=item * mandate_id

The mandate ID as originally provided.

=item * validation_reference

A reference to this electronic validation.

=back

=item * creditor

Information about the creditor; this can be used to check that the mandate
is for the correct creditor (just in case).  A hash reference with the
following keys:

=over

=item * name

The creditor's name as registered by the bank.

=item * creditor_id

The credit ID.

=back

=back

=cut

1;

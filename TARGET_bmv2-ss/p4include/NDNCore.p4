/**
 * This is a core include file defining all the NDN packet types as
 * prescribed in:
 * https://named-data.net/doc/ndn-tlv/
 */

#ifndef _NDN_CORE_
#define _NDN_CORE_

#define MAXIMUM_TLV_SIZE 0x7FffFFff /* FFffFFff */
/* Maximum tolerated size for a TLV. This is a theoretical limit, but if the
 * protocol runs over Ethernet, it should be 1500 at most.
 * Writing 0xf instead of 0x7 or uncommenting FFffFFff makes the 
 * P4 compiler yell that it is too large a value.
 */


// Define for the encoding of the length of a TLV block
// WARNING: Should you change these values, you should do so accordingly,
//maintaining their order and difference between one another.
#define ENCODING_1BYTE     0xFC 
#define ENCODING_2BYTE     0xFD
#define ENCODING_4BYTE     0xFE
#define ENCODING_8BYTE     0xFF

// Define for ethertype and type codes
#define ETHERTYPE_NDN      0x8624 // ethertype used by the NFD daemon
#define NDNTYPE_INTEREST   0x05
#define NDNTYPE_DATA       0x06


//Common fields
#define NDNTYPE_NAME            0x07
#define NDNTYPE_COMPONENT       0x08
#define NDNTYPE_SHA256DIGEST    0x01


//Interest packet
#define NDNTYPE_SELECTOR        0x09
#define NDNTYPE_NONCE           0x0a
#define NDNTYPE_LINK            0x0b
#define NDNTYPE_LIFETIME        0x0c
#define NDNTYPE_DELEGATION      0x1e

//Interest/selectors
#define NDNTYPE_MINSUFFIX       0x0d
#define NDNTYPE_MAXSUFFIX       0x0e
#define NDNTYPE_PKEYLOCATOR     0x0f 
#define NDNTYPE_EXCLUDE	        0x10 
#define NDNTYPE_CHILDSELECTOR   0x11 
#define NDNTYPE_MUSTBEFRESH     0x12 
#define NDNTYPE_KEYDIGEST       0x1d 
#define NDNTYPE_ANY             0x13


//Data packet
#define NDNTYPE_METAINFO        0x14
#define NDNTYPE_CONTENT         0x15
#define NDNTYPE_SIGNATUREINFO   0x16
#define NDNTYPE_SIGNATUREVAL    0x17

//Data/metainfo
#define NDNTYPE_VTYPE           0x18
#define NDNTYPE_FRESHPERIOD     0x19
#define NDNTYPE_FINALBLOCKID    0x1a

//Data/Signature
#define NDNTYPE_SIGNATURETYPE   0x1b
#define NDNTYPE_KEYLOCATOR      0x1c
#define NDNTYPE_KEYDIGEST       0x1d

#endif
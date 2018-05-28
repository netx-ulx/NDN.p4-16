#ifndef _P4_NDN_DEFINITIONS_
#define _P4_NDN_DEFINITIONS_

#include "./p4architecture/EtherNDNSampleArchitecture.p4"
//#include "./p4architecture/v1model.p4"


#define NDNTYPE_NAK  0x02
//NAK is defined here and not in the NDNCore.p4 architecture file
//because it's not part of the NDN packet specification. 0x02 is actually
//a reserved value. We are using it as the NDN type for NAKs, though
//the exact behavior that the NDN router should have towards NAKs has yet
//to be implemented.


#define HASH_LENGTH 64  //length for a component's hash digest in BITS.
   //Results in more collisions (collision in the sense of two different objects
   //with the same hash) if smaller, increases tables' sizes if bigger.

#define HASHTRAY_LENGTH 512//( 8 * 64 )
//ALWAYS PLACE MAXIMUM_COMPONENTS * HASH_LENGTH HERE!!
//The compiler rejects expressions in preprocessing

#define REGISTER_ARRAY_SIZE 4096
//Size of the register arrays. Most devices don't implement division remainder
//(the % operator), so it is recommended to type a multiple of 2 here.


#define CONTENTTYPE_LENGTH 8 //CONTENTTYPE_LENGTH is defined in bits
#define FRESHNESS_LENGTH 16 //Length of Metainfo/FreshnessPeriod in bits



typedef bit<32>  P4DualExtractArg; //This field represents the maximum suported
// size, in bits, of a varbit extraction.
// P4's current extract() method maps this value to 32 bits, so 2^32-1 bits
// is the maximum allowed size for a varbit field.

typedef bit<HASH_LENGTH> Hash;
typedef bit<NUMBER_OF_PORTS_LOG> portid_t;
typedef bit<HASHTRAY_LENGTH> hashestray_t;



//=============================================================
//================ I.     H E A D E R S =======================
//=============================================================

header Ethernet_h { // standard Ethernet header
   bit<48> dstAddr;
   bit<48> srcAddr;
   bit<16> etherType;
}


/** FORENOTE
 * BMv2 backend compiler does not accept variable length fields or header_
 * unions yet. The only purpose of the ifndef below is to have fixed length
 * fields in order to be able to test the program.
 *
 * Therefore, we are defining two cases:
 *
 * FIRST CASE: The macro TARGET_BMV2 is not defined. This means the
 * compiler accepts both unions and fixed-length fields. Once the BMv2 backend
 * has been fully developed to accept all P4-16 features, this should be the
 * default case.
 * In this case, the "TLV_h" type is a header_union that is either a (these are
 * the names as given by Signorello et al) smallTLV, a mediumTLV, etc.
 *
 * SECOND CASE: The macro TARGET_BMV2 is defined. In this case, the BMv2
 * backend compiler does not accept header unions and/or fixed-length fields.
 * In this case, the "TLV_h" type is a header with 8 bits of type, 8 bits of
 * length and 64 bits (8 bytes) of value. You can change this value below.
 */
#ifndef TARGET_BMV2

header smallTLV_h {
   bit<8> type;
   bit<8> lencode;
   varbit<2016> value;//is 252 * 8
}

header mediumTLV_h {
   bit<8> type;
   bit<8> lencode;
   bit<16> lenextension;
   varbit<0x7FFff> value;
}

header largeTLV_h {
   bit<8> type;
   bit<8> lencode;
   bit<32> lenextension;
   varbit<MAXIMUM_TLV_SIZE> value;  
}

/*header hugeTLV_h {
   bit<8> type;
   bit<8> lencode;
   bit<64> lenextension;
   varbit<0xFFFFffffFFFFffff> value; //The compiler does not accept this
}*/

header_union TLV_h {
   smallTLV_h smallTLV;
   mediumTLV_h mediumTLV;
   largeTLV_h largeTLV;
   //hugeTLV_h hugeTLV;
}

#else 
  #define VALUE_LENGTH 64 // 8 bytes

header TLV_h {
   bit<8> type;
   bit<8> lencode;
   bit<VALUE_LENGTH> value;
}

#endif //TARGET_BMV2

//======================================
/**
 * Instead of defining a new header union for TLVs whose Value is nested,
 * I decided to keep it a single header type. The parser decides if Value
 * should be extracted or not.
 */
header TL_h {
   bit<8> type;
   bit<8> lencode;
}

header Nonce_h {
   bit<8> type;
   bit<8> lencode;
   bit<32> value; //Nonce's value is always 32 bits.
}



// --- All the headers below are nodes of the NDN Data metainfo field
// The headers below were defined assuming metainfo will always be a small TLV.
// This is for no deep reason other than to avoid all the work involved in
// writing yet another subparser for this specific case.
header contentType_h { //TO BE REVISED.
   bit<8> type;
   bit<8> lencode;
   bit<CONTENTTYPE_LENGTH> value;
}

header freshnessPeriod_h { //TO BE REVISED.
   bit<8> type;
   bit<8> lencode;
   bit<FRESHNESS_LENGTH> value;//Tolerate a maximum of 2^16-1 ms of caching?
}

header finalBlockId_h {
   bit<8> type;
   bit<8> lencode;
   bit<
      #if (MAXIMUM_COMPONENTS_LOG <= 8)
      8
      #else
      16
      #endif
   > value; //Could just place MAX_COMPS_LOG here, but the parsed packet
   //should have a number of bits that is a multiple of 8.
}

//==========================================================
//================= II.  S T R U C T S =====================
//==========================================================

struct Parsed_packet {

   //1st: Ethernet.
   Ethernet_h     ethernet;
   
   //2nd: TLVs.
 #ifndef TARGET_BMV2 //The parser will decide if it should extract a value
   TLV_h       tl0;
   TLV_h       name;
 #else
   TL_h        tl0;
   TL_h        name;
 #endif
   
   TLV_h[MAXIMUM_COMPONENTS+1] components;
   
   
   //3rd: a) -- INTEREST
   TLV_h       selectors;//optional field
   
   Nonce_h     nonce; //Nonce value is always 4 bytes.
   
   TLV_h       lifetime;
   
   TLV_h       link;
   
   TLV_h       delegation;
   

   //3rd: b) -- DATA
   TL_h        metainfo; //Is type TL_h, which means only 'type' and 'length'
                         //are present. Assume 
   /* NOTE: In NDN Data packet format, all of Metainfo's fields are optional,
    * but Metainfo itself is not marked as such. Therefore, we assume we'll
    * always have at least Type and Length to deal with (lencode can be zero).
    * ( named-data.net/doc/ndn-tlv/data.html#metainfo )
    */
   contentType_h     contentType; //metainfo
   freshnessPeriod_h freshnessPeriod; //metainfo
   finalBlockId_h    finalBlockId; //metainfo
   
   TLV_h       content;
   
   TLV_h       signatureinfo;
   
   TLV_h       signaturevalue;
   
   
   //3rd: c) -- NAK
   TLV_h       errorcode;
}


struct Metadata {
   
   /*
    * The metadata fields below are for the subparser to fill. When I am in
    * the main parser, I do not know which of the header union members is
    * active, and therefore I cannot know which member to access in order to
    * fetch type or len. P4 header unions behave like tagged unions, and
    * therefore do not have the underlying C union memory quirks.
    * I.e., I cannot read from or write to a smallTLV_h.type and expect to be
    * reading from or writing to mediumTLV_h.type.
    */
   bit<8> lastTLVtype;
   bit<8> lastTLVlencode;
   P4DualExtractArg lastTLVsize;
   
   
   /*
    * The following field checks whether we have parsed a Link. If we have not,
    * then we cannot parse a SelectedDelegation.
    */
   bit<8> linktype;
   
   
   /*
    * General metadata used on various occasions.
    */
   bit<8> NDNpkttype;
   P4DualExtractArg pktsize;
   P4DualExtractArg namesize; //Used in Parser, but is 0 after all components
   //have been parsed.
   
   //the two above fields should be 64 bits if the P4 core library implements a
   //function that sets a varbit's dynamic length by reading more than 32 bits.
   bit<8> number_of_components; //used to count components
   hashestray_t hashtray;
   bit<9> next_egress_spec;
   
   bit<NUMBER_OF_PORTS> mcastports;//== 0 when pkt is not being cloned
   
   bit<1> parsed;//Indicates the packet reached a final parsing state and can
   //be processed. Necessary because bmv2 does not accept explicit transitions
   //to the reject state.
}



//==========================================================
//================= III.  E R R O R S ======================
//----------------------------------------------------------
error {
   //UnrecognizedPacketType,
   PARSER_P4_TLVTooLarge, //for TLVs whose length code is 255 or the number
   //of bytes to read can't be expressed in bits. Unsupported by P4-16.
   PARSER_NDN_UnknownPacketType, //Packets is neither Interest, Data or NAK.
   PARSER_NDN_ExpectedNameAfterTL0,
   PARSER_NDN_ExpectedComponent,
   
   PARSER_NDN_InnerTLVBiggerThanOuterTLV,
   PARSER_NDN_InnerTLVBiggerThanOuterTLV_NameBiggerThanTL0,
   PARSER_NDN_InnerTLVBiggerThanOuterTLV_ComponentBiggerThanName,
   PARSER_NDN_ComponentsLengthExceedsNameSize,
   PARSER_NDN_NumberOfComponentsAboveMaximum,
   
   PARSER_P4_CannotExpressVarbitLengthInBits, //a dual argument extract() needs
   //to be fed with a parameter indicating the number of bits to extract. TLVs
   //express it in bytes. If the number of bytes results in carry when
   //expressed in bits, then we cannot parse this packet

   PARSER_NDN_Interest_BadNonceLength,
   PARSER_NDN_Interest_DelegationWithoutLink,
   PARSER_NDN_Interest_DuplicateOptionalField_Lifetime,
   PARSER_NDN_Interest_DuplicateOptionalField_Link,
   PARSER_NDN_Interest_DuplicateOptionalField_Delegation,
   PARSER_NDN_Interest_ExpectedNonce,
   
   PARSER_NDN_Data_ExpectedMetainfo,
   PARSER_NDN_Data_MetainfoTooBig,
   PARSER_NDN_Data_ContentTypeBiggerThanOneByte,
   PARSER_NDN_Data_FreshnessPeriodBiggerThanTwoBytes,
   PARSER_NDN_Data_FinalBlockIdTooBig,
   
   PARSER_NDN_Data_ExpectedContent,
   PARSER_NDN_Data_ExpectedSignatureInfo,
   PARSER_NDN_Data_ExpectedSignatureValue
}

#endif  /* _P4_NDN_DEFINITIONS_ */

#include "defs.p4"

/**
 * RECALL:
 *
 * NDN packets are encoded are a series of nested Type-Length-Value (TLV).
 *
 * A TLV is composed of:
 * - An unsigned byte called TYPE.
 * - An unsigned byte called LENGTH, which we call 'lencode'.
 *  - If 'lencode' is 253, 254 or 255, then an extra 2, 4, or 8 unsigned
 * bytes respectively will follow LENGTH. We will call them EXTENDED LENGTH.
 * or LENGTH EXTENSION.
 *  - A stream of octects, called VALUE. The total number of octets is LENGTH
 * if LENGTH <= 252; otherwise, the number of octets is equal to the value in
 * EXTENDED LENGTH.
 *
 *
 * This work assumes NDN runs over Ethernet.
 * We expect NDN packets to be a single TLV, called 'tlv0', which inholds, in
 * its VALUE field, a series of other nested TLVs, the first of which is always
 * 
 */


//=============================================================================
//                          S U B     P A R S E R
//=============================================================================
//Extracts a TLV.
parser TLVreader(    //INVOCATION PARAMETERS
   packet_in b,                           //The packet under processing
   out TLV_h tlv,                         //A header_union TLV to be filled
   inout P4DualExtractArg size_tracker,   //Necessary to keep track of the size
   inout Metadata m,                      //Fill lastTLVtype and related fields
   bit<1> extractval                      //Extract value? 1 if yes, 0 if no
                                          //0 is used for nested TLVs, e.g.
                                          //TLV0 or TLVN.
 )
{
   
   //------------- A T T R I B U T E S ----------------
   bit<16> lencode;//we made it an attribute instead of a local variable for the
   //mere reason it's also used in state extract_small_TLV after state start
   
   P4DualExtractArg amountToExtract; //Keeps track of how much should be
   //extracted, in bytes.
   
   
   //------------- P R O C E S S I N G ----------------
   //------ Find the size of the next TLV -------------
   state start {
      lencode = b.lookahead<bit<16>>() & 0x00FF;

      verify(lencode != 255, error.P4_TLVTooLarge);

      transition select( lencode ) {
         0..(ENCODING_2BYTE-1) : extract_small_TLV;
         ENCODING_2BYTE : extract_medium_TLV;
         ENCODING_4BYTE : extract_large_TLV;
         // ENCODING_8BYTE : extract_huge_TL;
         
         /* NOTE: The last line (ENCODING_8BYTE) is commented out. With this method,
          * extract( ... , bit<32> variableFieldSize),
          * P4 does not support extracting more than an amount expressed in 32 bits.
          */
      }
   }
   
   
   //-------- SMALL --------
   //Extract a small TLV: 8 bits of type, 8 bits of lencode.
   state extract_small_TLV {
      
      //1ST: Update tracker with the size of the portion of data we're extracting
      amountToExtract  = (P4DualExtractArg) lencode
         * ((P4DualExtractArg) extractval);
      size_tracker     = size_tracker - 2 - amountToExtract;
      
      //2ND: Perform the extraction
      b.extract(tlv.smallTLV, amountToExtract << 3);
      
      //3RD: Update metadata so the main parser has information on the most
      //recently extracted TLV.
      m.lastTLVtype    = tlv.smallTLV.type;
      m.lastTLVlencode = tlv.smallTLV.lencode;
      m.lastTLVsize    = (P4DualExtractArg) tlv.smallTLV.lencode;
      
      //4TH: Accept -- returns to the point where the subparser was called
      transition accept;
   }
   
   
   //-------- MEDIUM --------
   //Extract a medium TLV: 8 types of type, 8 of lencode, and 16 of extension
   state extract_medium_TLV {
      
      //1ST: Record the size of the TLV we're gonna extract. Do that by looking
      //ahead for the type, length, and extension, and grabbing the latter.
      m.lastTLVsize = b.lookahead<bit<32>>() & 0x0000FFff;
      
      //2ND: Check how much we need to extract and update size tracker accordingly
      amountToExtract = m.lastTLVsize * ( (P4DualExtractArg) extractval);
      size_tracker = size_tracker - 4 - amountToExtract;
      //1 byte of type + 1 byte of length + 2 bytes of extension = 4
      
      //3RD: Perform the extraction.
      b.extract(tlv.mediumTLV, amountToExtract << 3);
      
      //4TH: Update metadata.
      m.lastTLVtype = tlv.mediumTLV.type;
      m.lastTLVlencode = ENCODING_2BYTE;
      
      //5TH: Accept -- returns to the point where the subparser was called
      transition accept;
   }
   
   
   //-------- LARGE --------
   //Extract a large TLV: 8 types of type, 8 of lencode, and 32 of extension
   state extract_large_TLV {
      
      //1ST: Record the size of the TLV we're gonna extract. Do that by looking
      //ahead for the type, length, and extension, and grabbing the latter.
      m.lastTLVsize = (P4DualExtractArg) (b.lookahead<bit<48>>() & 0x0000FFffFFff);
      
      //2ND: Check how much we need to extract and update size tracker accordingly
      amountToExtract = m.lastTLVsize * ((bit<32>) extractval);
      size_tracker = size_tracker - 6 - amountToExtract;
      //1 byte of type + 1 byte of length + 4 bytes of extension = 6
      
      //3RD: Verify cases where we can't extract this TLV correctly  
      verify((m.lastTLVsize & 0xE0000000) == 0,
         error.P4_CannotExpressVarbitLengthInBits);
      //remember that the dual parameter extract() takes the length, in BITS. 
      //If this NDN's length is more BYTES than can be expressed in BITS,
      //then we cannot parse this packet.
      //Practical implication: When multiplying by 8 aka shifting left by 3,
      //there must NOT be carry => the 3 leftmost bits must be cleared.
      
      //4TH: Perform the extraction
      b.extract(tlv.largeTLV, m.lastTLVsize << 3);
      
      //5TH: Update metadata.
      m.lastTLVtype = tlv.largeTLV.type;
      m.lastTLVlencode = ENCODING_4BYTE;     
      
      //6TH: Accept -- returns to the point where the subparser was called
      transition accept;
   }
   
}




//=============================================================================
//                          M A I N     P A R S E R
//=============================================================================
parser InitialParser(packet_in b, out Parsed_packet p, inout Metadata m, inout
standard_metadata_t standard_metadata) {
   
   // ------------------------- A T T R I B U T E S ---------------------------
   TLVreader() TLVr;
   Hash digest_var;//Temporary that receives the result of hash() calculation
   bit<8> parserattribute_tlv0lencode;
   bit<8> parserattribute_namelen;

   
   
   // ------------------------- P R O C E S S I N G ---------------------------
   
   
   //STEP 1 -- Extract the Ethernet header and check if it is NDN type.
   state start {
      b.extract( p.ethernet );

      transition select( p.ethernet.etherType ) {
         0x8624   : parsing_general;
         //default  : reject;  //bmv2 doesn't support explicit reject transition
      }
   }



   //STEP 2 -- Parse tl0, Name, and later Components. Omnipresent fields.
   state parsing_general {
      
      //=======================================================================
      // ===== 1ST: --- TLV0.
      //=======================================================================
      m.pktsize = 0x7FffFFff; //Initialize with this value to avoid carry.
      //It will also be useful to make verifications regarding link-layer MTU.
      
      TLVr.apply(b, p.tl0, m.pktsize, m, 0);

      //Check if packet's size is larger than our MTU
      verify( ((m.lastTLVlencode < ENCODING_2BYTE) /*&& (m.lastTLVsize < MTU)*/)
      || ((m.lastTLVlencode < ENCODING_4BYTE) && ((0x7FffFFff - m.pktsize - 4) < MTU)),
            error.P4_TLVTooLarge);
      
      parserattribute_tlv0lencode = m.lastTLVlencode;
      m.NDNpkttype = m.lastTLVtype;
      m.pktsize = m.lastTLVsize;

      verify( m.lastTLVtype == NDNTYPE_INTEREST
          || m.lastTLVtype == NDNTYPE_DATA
          || m.lastTLVtype == NDNTYPE_NAK, 
            error.NDN_UnknownPacketType);
      //later we will branch off depending on the type
      //but verify here to immediately discard this packet if it is malformed.
      
      //=======================================================================
      // ===== 2ND: --- Name or TLVN
      //=======================================================================
      TLVr.apply(b, p.name, m.pktsize, m, 0);
      
      m.namesize = m.lastTLVsize;
      
      verify( m.lastTLVtype == NDNTYPE_NAME,
            error.NDN_ExpectedNameAfterTL0);
      verify( m.lastTLVlencode < parserattribute_tlv0lencode 
            || m.namesize < m.pktsize,
            error.NDN_InnerTLVBiggerThanOuterTLV_NameBiggerThanTL0 );
      
      //=======================================================================
      // ===== 3RD: --- Prepare metadata
      //=======================================================================
      m.number_of_components = 0;
      m.hashtray = 0;
      m.mcastports = 0;
      parserattribute_namelen = m.lastTLVlencode;
      
      transition parsing_components;
   }
   


   //STEP 3 -- Parse Components.
   state parsing_components {
   
      //=======================================================================
      // ===== 4TH: --- Extract a component
      //=======================================================================
      // ===== 4.0:  -- Inspect starting conditions
      verify( m.number_of_components < MAXIMUM_COMPONENTS,
            error.NDN_NumberOfComponentsAboveMaximum );
      
      // ===== 4.1: -- Extract a component and decrement namesize
      TLVr.apply(b, p.components[m.number_of_components], m.namesize, m, 1);
      
      // ===== 4.2: -- Verify types and lengths
      verify( m.lastTLVtype == NDNTYPE_COMPONENT, 
         error.NDN_ExpectedComponent );
      verify( m.lastTLVlencode <= parserattribute_namelen,
         error.NDN_InnerTLVBiggerThanOuterTLV_ComponentBiggerThanName );
      verify( m.lastTLVsize <= m.namesize,
         error.NDN_InnerTLVBiggerThanOuterTLV_ComponentBiggerThanName );
      // if the above condition isn't met, then the packet has a name size
      // bigger than the sum of all components

      // ===== 4.3: -- Compute hash
      transition select( m.lastTLVlencode ) {
         0..(ENCODING_2BYTE-1): hash_small_TLV;
         ENCODING_2BYTE: hash_medium_TLV;
         ENCODING_4BYTE: hash_large_TLV;
      }
   }


   state hash_small_TLV {
      hash(digest_var, HashAlgorithm.crc32, (Hash) 0,
          p.components[m.number_of_components].smallTLV.value,
          (Hash) 0xFFffFFff);
      transition post_hash;
   }


   state hash_medium_TLV {
      hash(digest_var, HashAlgorithm.crc32, (Hash) 0,
          p.components[m.number_of_components].mediumTLV.value,
          (Hash) 0xFFffFFff);
      transition post_hash;
   }
   
   state hash_large_TLV {
      hash(digest_var, HashAlgorithm.crc32, (Hash) 0,
          p.components[m.number_of_components].largeTLV.value,
          (Hash) 0xFFffFFff);
      transition post_hash;
   }
   
   
   state post_hash {
      //=======================================================================
      // ===== 5TH: --- Update hashtray.
      //=======================================================================
      //4.1 Shift the accumulator left by HASH_LENGTH.
      //4.2 Then BIT-OR the accumulator with the hash we just calculated.
      
      // For example, if the current components digest is 0xEE and the hash
      // calculation yielded 0xAA, then after this line m.hashtray should
      // become 0xEEAA.
      m.hashtray = (m.hashtray << HASH_LENGTH) | (bit<HASHTRAY_LENGTH>)
         digest_var;
      
      //=======================================================================    
      // ===== 6TH: -- Update number of components
      //=======================================================================
      m.number_of_components = m.number_of_components + 1;
      
      //=======================================================================    
      // ===== 7TH: -- Transition
      //=======================================================================    
      transition select( m.namesize ) {
         0: accept;
         default: parsing_components;
      }     
   }


   //STEP 4 -- Decide what packet type we're dealing with. Parsing progresses
   //differently depending on each one.
   state parsing_by_packet_type {

       m.hashtray = m.hashtray <<
         ((MAXIMUM_COMPONENTS - m.number_of_components) * HASH_LENGTH);
      /*
       * After the above line, the hash of a name "a/b" (2 components)
       * becomes (assuming 4 maximum components):
       *
       * [ hash(a) ] [ hash(b) ] [0x00000000] [0x00000000]
       *
       * from:
       *
       * [0x00000000] [0x00000000] [ hash(a) ] [ hash(b) ]
       *
       * We need to push things to the most significant bytes because that's
       * how longest prefix match masks are applied.
       */      
      
      transition select( m.NDNpkttype ) {
         NDNTYPE_INTEREST: parsing_interest;
#if defined(CHECK_SIGNATURES) || defined(CONTENT_STORE)
         NDNTYPE_DATA: parsing_data;
#else
         NDNTYPE_DATA: accept;
#endif // defined(CHECK_SIGNATURES) || defined(CONTENT_STORE)
         NDNTYPE_NAK: parsing_nak;
      }
   }


//================================================
   //NAK
   state parsing_nak {
      TLVr.apply(b, p.errorcode, m.pktsize, m, 1);
      m.parsed = 1;
      transition accept;
   }
   


//================================================
   //INTEREST
   state parsing_interest {
      transition select( b.lookahead<bit<8>>() ) {
         NDNTYPE_SELECTOR: selectors;
         NDNTYPE_NONCE: nonce;
         //default: reject; //bmv2 does not support explicit transition to reject
      }

   }
   
   //INTEREST SELECTORS
   state selectors {
      TLVr.apply(b, p.selectors, m.pktsize, m, 1);
      //no need to verify; if we transitioned to this state, then the type was correct.
      
      transition nonce;
   }
   
   //INTEREST NONCE
   state nonce {
      b.extract( p.nonce );
      m.pktsize = m.pktsize - 6;//1 bytes of type, 1 of lencode, 4 of value
      
      verify( p.nonce.type == NDNTYPE_NONCE, error.NDN_Interest_ExpectedNonce );
      verify( p.nonce.lencode == 4, error.NDN_Interest_BadNonceLength );
      //"The Nonce carries a randomly-generated 4-octet long byte-string.
      // The combination of Name and Nonce should uniquely identify an Interest.
      // This is used to detect looping Interests." 
      // (from named-data.net/doc/ndn-tl/interest.html)
      
      m.linktype = 0;
      m.parsed = 1;
      
      transition check_global_sizetracker;
   }
   
   //INTEREST -- To avoid defining more states, we will come back to this one and
   //evaluate our m.pktsize each time. We must ensure there's still more of the
   //packet to be read. Only then can we attempt to parse optional packet fields.
   //If we call b.lookahead() at the end of the packet, we get an error.
   state check_global_sizetracker {
      transition select( m.pktsize ) {
         0: accept;
         _: others;
      }  
   }
 
   state others {
      //marking default as accept ignores further unrecognized types.
      //(Should this be the default behavior?)
      transition select( b.lookahead<bit<8>>() ) {
         NDNTYPE_LIFETIME   : lifetime;
         NDNTYPE_DATA       : link;
         NDNTYPE_DELEGATION : delegation;
         default            : accept;
      }
   }
   
   state lifetime {
      verify( !p.lifetime.smallTLV.isValid() && !p.lifetime.mediumTLV.isValid() &&
            !p.lifetime.largeTLV.isValid(),
            error.NDN_Interest_DuplicateOptionalField_Lifetime);
      //if this verify() checks out, then lifetime is yet to be filled.
      
      TLVr.apply(b, p.lifetime, m.pktsize, m, 1);
      //No verification performed on type: if we transitioned here, then the type was
      //accurate

      transition check_global_sizetracker;
   }
   
   state link {
      verify( !p.link.smallTLV.isValid() && !p.link.mediumTLV.isValid() &&
            !p.link.largeTLV.isValid(),
            error.NDN_Interest_DuplicateOptionalField_Link );

      TLVr.apply(b, p.link, m.pktsize, m, 1);
      m.linktype = NDNTYPE_DATA;

      transition check_global_sizetracker;
   }
   
   state delegation {
      verify( !p.delegation.smallTLV.isValid() && !p.delegation.mediumTLV.isValid() &&
            !p.delegation.largeTLV.isValid(),
            error.NDN_Interest_DuplicateOptionalField_Lifetime );
      verify( m.linktype == NDNTYPE_DATA,
             error.NDN_Interest_DelegationWithoutLink );
      //"If Link field is not present, the SelectedDelegation field MUST NOT be present."
      //(from named-data.net/doc/ndn-tl/interest.html)
      //Therefore, if SelectedDelegation is present, so is Link
      
      TLVr.apply(b, p.delegation, m.pktsize, m, 1);

      transition check_global_sizetracker;
   }

   
//================================================
   //DATA
   state parsing_data {
      //1ST -- Metainfo type and length
      b.extract(p.metainfo);
      
      verify( p.metainfo.type == NDNTYPE_METAINFO, error.NDN_Data_ExpectedMetainfo);
      verify( p.metainfo.lencode <= 4 + FRESHNESS_LENGTH + CONTENTTYPE_LENGTH +
             (MAXIMUM_COMPONENTS_LOG >> 3)+1, error.NDN_Data_MetainfoTooBig);         
      /* NOTE: In NDN Data packet format, all of Metainfo's fields are optional,
       * but Metainfo itself is not marked as such. Therefore, we assume we'll always
       * have at least Type and Length to deal with (lencode can be zero).
       * ( named-data.net/doc/ndn-tlv/data.html#metainfo )
       */
      
      m.pktsize = m.pktsize - 2 - (P4DualExtractArg) p.metainfo.lencode;

      transition select( p.metainfo.lencode ) {
         0 : parsing_data_final;
         _ : parse_data_optional_fields;
      }
   }

   
   //1ST * -- Check which field we're going to extract   
   state parse_data_optional_fields {

      transition select( b.lookahead<bit<8>>() ) {
         NDNTYPE_VTYPE : parse_optional_contentType;
         NDNTYPE_FRESHPERIOD: parse_optional_freshnessPeriod;
         NDNTYPE_FINALBLOCKID: parse_optional_finalBlockId;
         //_ : reject; //bmv2 does not support explicit transitions to reject
      }
   }
   
   //1ST a) -- Metainfo/ContentType
   state parse_optional_contentType {
      b.extract(p.contentType);

      verify( p.contentType.lencode == CONTENTTYPE_LENGTH,
             error.NDN_Data_ContentTypeBiggerThanOneByte );
      //No need to verify type: if type isn't NDNTYPE_CONTENTTYPE then we don't reach here
      
      transition select( b.lookahead<bit<8>>() ) {
         NDNTYPE_FRESHPERIOD: parse_optional_freshnessPeriod;
         NDNTYPE_FINALBLOCKID: parse_optional_finalBlockId;
         NDNTYPE_CONTENT: parsing_data_final;
         //_ : reject; //bmv2 does not support explicit transitions to reject
      }
   }
   
   //1ST b) -- Metainfo/FreshnessPeriod
   state parse_optional_freshnessPeriod {
      b.extract(p.freshnessPeriod);
      
      verify( p.freshnessPeriod.lencode == FRESHNESS_LENGTH,
             error.NDN_Data_FreshnessPeriodBiggerThanTwoBytes);
      
      transition select( b.lookahead<bit<8>>() ) {
         NDNTYPE_FINALBLOCKID: parse_optional_finalBlockId;
         NDNTYPE_CONTENT: parsing_data_final;
         //_ : reject; //bmv2 does not support explicit transitions to reject       
      }
   }
   
   //1ST c) -- Metainfo/FinalBlockId
   state parse_optional_finalBlockId {
      b.extract(p.finalBlockId);
      
      verify( p.finalBlockId.lencode <= (MAXIMUM_COMPONENTS >> 3),
             error.NDN_Data_FinalBlockIdTooBig);
      // Verifying p.finalBlockId.value is unneeded: if it is bigger than
      // MAXIMUM_COMPONENTS, it exceeds the representation.
      
      transition parsing_data_final;
   }
   
   //2ND -- Everything else remaining in the Data packet 
   state parsing_data_final
   {
      TLVr.apply(b, p.content, m.pktsize, m, 1);
      verify( m.lastTLVtype == NDNTYPE_CONTENT, error.NDN_Data_ExpectedContent );
      
      m.parsed = 1;
      
   #ifdef CHECK_SIGNATURES
      TLVr.apply(b, p.signatureinfo, m.pktsize, m, 1);
      verify( m.lastTLVtype == NDNTYPE_SIGNATUREINFO,
            error.NDN_Data_ExpectedSignatureInfo );
      
      TLVr.apply(b, p.signaturevalue, m.pktsize, m, 1);
      verify( m.lastTLVtype == NDNTYPE_SIGNATUREVAL,
            error.NDN_Data_ExpectedSignatureValue );
   #endif // CHECK_SIGNATURES
      
      transition accept;
   }
}

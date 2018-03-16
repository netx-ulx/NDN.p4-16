#include "defs.p4"

parser InitialParser(packet_in b, out Parsed_packet p, inout Metadata m, inout standard_metadata_t standard_metadata) {
   
   state start {
      b.extract( p.ethernet );
      
      transition select( p.ethernet.etherType ) {
         0x8624: parse_tl0;
      }
   }
   
   
   
   state parse_tl0 {
      b.extract( p.tl0 );
      b.extract( p.name );
      
      m.NDNpkttype = p.tl0.type;
      m.pktsize = (P4DualExtractArg) p.tl0.lencode - m.namesize - 2;
      m.namesize = (P4DualExtractArg) p.name.lencode;
      m.number_of_components = 0;
      
      transition parse_components;
   }
   
   
   state parse_components {
   
      b.extract( p.components[0] );
   
      verify( (P4DualExtractArg) p.components[0].lencode <= m.namesize,
             error.PARSER_NDN_ComponentsLengthExceedsNameSize );
      
      m.namesize = m.namesize - 2 - (VALUE_LENGTH >> 3);
      m.number_of_components = m.number_of_components + 1;
      
      transition select( m.namesize ) {
         0 : parse_by_pkttype;
         _ : parse_components_two;
      }
   }
   
   
   state parse_components_two {
      b.extract( p.components[1] );
   
      verify( (P4DualExtractArg) p.components[1].lencode <= m.namesize,
             error.PARSER_NDN_ComponentsLengthExceedsNameSize );
      
      m.namesize = m.namesize - 2 - (VALUE_LENGTH >> 3);
      m.number_of_components = m.number_of_components + 1;
      
      transition select( m.namesize ) {
         0 : parse_by_pkttype;
         _ : parse_components_three;
      }
   }
   
   state parse_components_three {
      b.extract( p.components[2] );
   
      verify( (P4DualExtractArg) p.components[2].lencode <= m.namesize,
             error.PARSER_NDN_ComponentsLengthExceedsNameSize );
      
      m.namesize = m.namesize - 2 - (VALUE_LENGTH >> 3);
      m.number_of_components = m.number_of_components + 1;
      
      transition select( m.namesize ) {
         0 : parse_by_pkttype;
         _ : parse_components_four;
      }
   }  
   
   state parse_components_four {
      b.extract( p.components[3] );
   
      verify( (P4DualExtractArg) p.components[3].lencode <= m.namesize,
             error.PARSER_NDN_ComponentsLengthExceedsNameSize );
      
      m.namesize = m.namesize - 2 - (VALUE_LENGTH >> 3);
      m.number_of_components = m.number_of_components + 1;
      
      transition select( m.namesize ) {
         0 : parse_by_pkttype;
      }
   }     
   
   
   state parse_by_pkttype {
      transition select( m.NDNpkttype ) {
         NDNTYPE_DATA: parse_data;
         NDNTYPE_INTEREST: parse_interest;
      }
   }
   
   
   state parse_data {
#if defined(CONTENT_STORE) || defined(CHECK_SIGNATURES)
      b.extract( p.content );
#endif
      
      p.tl0.type = 0xff;
      
      m.parsed = 1;
      
      transition accept;
   }
   
   
   state parse_interest {
      //extract( p.selectors );
      b.extract( p.nonce );
      
      m.parsed = 1;
      
      p.tl0.type = 0xfe;
      
      transition accept;
   }
}

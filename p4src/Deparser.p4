#include "defs.p4"

control TopDeparser(packet_out b, in Parsed_packet p) {
   
   apply {
      b.emit(p.ethernet);
      
      b.emit(p.tl0);
      b.emit(p.name);
      b.emit(p.components);
      
      //INTEREST
      //The single-parameter emit() method checks the validity bit.
      //If some header wasn't filled, it isn't actually emitted.
         b.emit(p.selectors);
         b.emit(p.nonce);
         b.emit(p.lifetime);
         b.emit(p.link);
         b.emit(p.delegation);
      //}
      
      //DATA
   #if defined(CHECK_SIGNATURES) || defined(CONTENT_STORE)
         b.emit(p.metainfo);
         b.emit(p.contentType);
         b.emit(p.freshnessPeriod);
         b.emit(p.finalBlockId);
   
         b.emit(p.content);
   #endif
   #ifdef CHECK_SIGNATURES
         b.emit(p.signatureinfo);
         b.emit(p.signaturevalue);
   #endif //CHECK_SIGNATURES
      //}
      
         b.emit(p.errorcode);
   }
}

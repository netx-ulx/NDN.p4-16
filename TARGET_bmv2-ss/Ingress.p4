#include "defs.p4"

struct value_for_hash_t {
  bit<VALUE_LENGTH> value;
}


control TopIngress(inout Parsed_packet p, inout Metadata m,
                   inout standard_metadata_t stdm) {

   //PIT declaration
   register<bit<NUMBER_OF_PORTS>>(REGISTER_ARRAY_SIZE) PIT;
   bit<32> lastidx = 0;


   #include "Actions.p4"

   
   
   /**
    * Sets the packet's output port based on the Interest or Data's Name.
    * @param port: Port associated with this name. Provided by the table.
    */
   action Set_outputport(portid_t port)
   { stdm.egress_spec = (bit<9>) port; }

   
   
   /**
    * Keeps the control-plane maintained association of names and output ports
    * for the packet.
    * 
    * EXAMPLE
    * __________________________________________________
    *| hashtray             MASK    OUTPUT_PORT
    *|
    *| hash("a/b/c")                 /48     5
    *| hash("fciencias.ulisboa.pt")  /16     0
    *| hash("listsp4.org")           /16     5
    *| ...
    *|__________________________________________________
    */
   table fib {
      key = {
         m.hashtray : lpm;
      }
      actions = {
         Set_outputport;//If nonce not yet seen.
         Send_to_cpu;   //If no match, we need to send a NACK backwards
         Drop;          //...Or not
      }
      
      default_action = Drop;
   }

   
   
   /**
    * This action changes the metadata field "cloning_to_ports".
    * Given any bit pattern, "cloning_to_ports" is shifted right until a raised
    * bit (i.e., a bit whose value is 1) is found. egress_spec is set to the
    * same amount.
    *
    * @param dist - Distance to the rightmost raised bit.
    * @ensures stdm.egress_spec == dist
    */
   action ShiftToRightmostRaisedBit(bit<NUMBER_OF_PORTS_LOG> dist) { 
      stdm.egress_spec = (bit<9>) dist;
      m.mcastports = m.mcastports >> dist;
   }
   
   
   /**
    * Given the bit pattern in m.mcastports, the distance to the
    * rightmost raised/set bit (i.e. bit whose value is 1) is fetched from the
    * table entries. m.mcastports is shifted accordingly, and egress_spec
    * is set to the same amount.
    *
    * This is part of the multicast process. Each bit that is raised in
    * m.mcastports represents a port that awaits a copy of the Data we're
    * receiving.
    */
   table getNextFlaggedPort {
      
      key = { m.mcastports : ternary; }
      
      actions = {
         ShiftToRightmostRaisedBit;
         Drop;
      }
      
      const default_action = Drop();
      
      const entries = {
      // (pattern &&& mask)
         1     &&& 0b1    : ShiftToRightmostRaisedBit(0);
         2     &&& 0b11   : ShiftToRightmostRaisedBit(1);
         4     &&& 0b111  : ShiftToRightmostRaisedBit(2);
         8     &&& 0b1111 : ShiftToRightmostRaisedBit(3);
         16    &&& 0x1F   : ShiftToRightmostRaisedBit(4);
         32    &&& 0x3F   : ShiftToRightmostRaisedBit(5);
         64    &&& 0x7F   : ShiftToRightmostRaisedBit(6);
         128   &&& 0xFF   : ShiftToRightmostRaisedBit(7);
         256   &&& 0x1FF  : ShiftToRightmostRaisedBit(8);
         512   &&& 0x3FF  : ShiftToRightmostRaisedBit(9);
         1024  &&& 0x7FF  : ShiftToRightmostRaisedBit(10);
         2048  &&& 0xFFF  : ShiftToRightmostRaisedBit(11);
         4096  &&& 0x1FFF : ShiftToRightmostRaisedBit(12);
         8192  &&& 0x3FFF : ShiftToRightmostRaisedBit(13);
         16384 &&& 0x7FFF : ShiftToRightmostRaisedBit(14);
         32768 &&& 0xFFFF : ShiftToRightmostRaisedBit(15);
      }
      
   }
   


  //**** ----- CONTROL PIPELINE STARTS HERE ----- ****
   apply {

      // The code below drops the packet if it was not parsed successfully.
      // This is necessary because BMv2 backend compiler does not accept
      // explicit transitions to reject, and BMv2 simple_switch does not drop
      // packets when an error occurs in parsing.
      if (m.parsed == 0) {
         mark_to_drop();
         return;
      }
      
   //temp variables
      Hash digest_ret;
      value_for_hash_t v;
      bit<32> index;
      // Using this classic method of indexing into a hash table won't work.
      // Due to the way the hashtray is built, the rightmost bits are almost
      // always zeroes.

      v.value = p.components[0].value;
      hash(digest_ret, HashAlgorithm.identity, (Hash) 0, v, (Hash) 0xFFffFFffFFffFFff);
      m.hashtray = (bit<HASHTRAY_LENGTH>) digest_ret;
      m.hashtray = m.hashtray << HASH_LENGTH;
      
      index = lastidx;

      if (lastidx >= REGISTER_ARRAY_SIZE)
        lastidx = 0;
      else
        lastidx = lastidx + 1;
      //random(index, 0, REGISTER_ARRAY_SIZE);
      //index = (bit<32>) digest_ret & 0b111; //built with 3 bits of each component
      
      //COMPONENT 2 (component 1 exists because all names have at least 1)
      if (m.number_of_components > 1) {
         v.value = p.components[1].value;
         hash(digest_ret, HashAlgorithm.identity, (Hash) 0, v, (Hash) 0xFFffFFffFFffFFff);
         m.hashtray = m.hashtray | (bit<HASHTRAY_LENGTH>) digest_ret;
         //index = (index << 3) | (bit<32>)(digest_ret & 0b111);
      }
      
      m.hashtray = m.hashtray << HASH_LENGTH;
      
      //COMPONENT 3
      if (m.number_of_components > 2) {
         v.value = p.components[2].value;
         hash(digest_ret, HashAlgorithm.identity, (Hash) 0, v, (Hash) 0xFFffFFffFFffFFff);
         m.hashtray = m.hashtray | (bit<HASHTRAY_LENGTH>) digest_ret;
         //index = (index << 3) | (bit<32>)(digest_ret & 0b111);
      }
      
      m.hashtray = m.hashtray << HASH_LENGTH;
      
      //COMPONENT 4
      if (m.number_of_components > 3) {
         v.value = p.components[3].value;
         hash(digest_ret, HashAlgorithm.identity, (Hash) 0, v, (Hash) 0xFFffFFffFFffFFff);
         m.hashtray = m.hashtray | (bit<HASHTRAY_LENGTH>) digest_ret;
         //index = (index << 3) | (bit<32>)(digest_ret & 0b111);
      }

      m.hashtray = m.hashtray << HASH_LENGTH;     
     
      if (m.number_of_components > 4) {
         v.value = p.components[4].value;
         hash(digest_ret, HashAlgorithm.identity, (Hash) 0, v, (Hash) 0xFFffFFffFFffFFff);
         m.hashtray = m.hashtray | (bit<HASHTRAY_LENGTH>) digest_ret;
         //index = (index << 3) | (bit<32>)(digest_ret & 0b111);
      }     
      
      m.hashtray = m.hashtray << HASH_LENGTH;     
     
      if (m.number_of_components > 5) {
         v.value = p.components[5].value;
         hash(digest_ret, HashAlgorithm.identity, (Hash) 0, v, (Hash) 0xFFffFFffFFffFFff);
         m.hashtray = m.hashtray | (bit<HASHTRAY_LENGTH>) digest_ret;
         //index = (index << 3) | (bit<32>)(digest_ret & 0b111);
      } 
     
      m.hashtray = m.hashtray << HASH_LENGTH;     
     
      if (m.number_of_components > 6) {
         v.value = p.components[6].value;
         hash(digest_ret, HashAlgorithm.identity, (Hash) 0, v, (Hash) 0xFFffFFffFFffFFff);
         m.hashtray = m.hashtray | (bit<HASHTRAY_LENGTH>) digest_ret;
         //index = (index << 3) | (bit<32>)(digest_ret & 0b111);
      }
     
      m.hashtray = m.hashtray << HASH_LENGTH;
     
      if (m.number_of_components > 7) {
         v.value = p.components[7].value;
         hash(digest_ret, HashAlgorithm.identity, (Hash) 0, v, (Hash) 0xFFffFFffFFffFFff);
         m.hashtray = m.hashtray | (bit<HASHTRAY_LENGTH>) digest_ret;
         //index = (index << 3) | (bit<32>)(digest_ret & 0b111);
      }
     
      
/* ============================================================================
 * --- PACKET TYPE:     N A K
 * ============================================================================
 * When a NAK is received from upstream, it will come as a response to a Data
 * packet. The NAK by a router when it is congestioned, has no path for the
 * requested name, or some other reason. That reason should be indicated by a
 * field in the NAK packet.
 *
 * In this work, we decided that a NAK packet is a packet type by itself. Other
 * works in NDN consider NAK packet to be a subtype of Data.
 *
 * Support for NAK is incomplete.
 */
      if (m.NDNpkttype == NDNTYPE_NAK) {
         
         Send_to_cpu();//try alternative paths
      
      }  
/* ============================================================================
 * --- PACKET TYPE:     D A T A
 * ============================================================================
 * According to the NDN communications protocol, when a Data is received:
 *
 *    1. The PIT should be checked. No match means this is spurious Data.
 *       It should therefore be dropped.
 *
 *    2. If there is a match, we cache the packet and clone to every port
 *       whence we received a request.
 */
      else if (m.NDNpkttype == NDNTYPE_DATA) {
         
         //1ST: Consult PIT to see if we were expecting this Data
         // Place the port array of requesting faces in m.mcastports
         PIT.read(m.mcastports, index);


         //2ND: Add to the CS and clone to every output port.
         if (m.mcastports == 0) { //No entry exists => spurious Data

            Drop();

         } else {

            //--- a) add to the content store
            

            //--- b) clean the pit entry
            PIT.write(index, 0);


            //--- c) mirror the Data packet to all requesting faces
            getNextFlaggedPort.apply();

         }
         
      } //NDNTYPE_DATA
       
/* ============================================================================
 * --- PACKET TYPE:     I N T E R E S T
 * ============================================================================
 * According to the NDN communications protocol, when an Interest is received:
 *
 *    1. The content store is checked in an attempt to serve directly.
 *
 *    2. If there is no match in the content store, then we access the PIT.
 *       An existing entry for the same name means this data has already been
 *       requested. We simply add the incoming port to a list of requesting
 *       ports.
 *
 *    3. If no match exists on the content store or the PIT, then this is the
 *       first request for this name. Forward it according to the FIB rules.
 */
      else //Parser rejected other packet types; only Interest is possible here
      {
         //Else we'll have to record this Interest in the PIT and nonces.
         PIT.read(m.mcastports, index);

         //if (m.mcastports == 0) { //First Interest seen for this name
            switch (fib.apply().action_run) {
               Drop: { return; } //Forward if entry exists, otherwise Drop
               //return is necessary to avoid altering the PIT
               //TODO: Should send NAK packet towards ingress_port
            }; 
         //}            

         // The bit<8> cast below is necessary because BMv2 tolerates a
         // shift count of a value expressed in a maximum of 8 bits.
         // "ingress_port" is 9 bits.
         m.mcastports = m.mcastports | 
            ((bit<NUMBER_OF_PORTS>) 1 << ((bit<8>) stdm.ingress_port));
            
         PIT.write(index, m.mcastports);

	 m.mcastports = 0;
      }
   }
}

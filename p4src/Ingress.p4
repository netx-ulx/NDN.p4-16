#include "defs.p4"

control TopIngress(inout Parsed_packet p, inout Metadata m,
                   inout standard_metadata_t stdm) {

  //===== P E N D I N G    I N T E R E S T    T A B L E =======
  //The bit vectors are stored in 'PIT'
  //There is no hashmap mechanism in P4. To make sure two Interest names
  //don't index into the same position, we need 'PITnames' to desambiguate
  register<bit<NUMBER_OF_PORTS>>(REGISTER_ARRAY_SIZE) PIT;
  register<bit<HASHTRAY_LENGTH>>(REGISTER_ARRAY_SIZE) PITnames;


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
   *| hashtray                      MASK    OUTPUT_PORT
   *|
   *| hash("a/b/c")                 /192    5
   *| hash("fciencias.ulisboa.pt")  /64     0
   *| hash("listsp4.org")           /64     5
   *| ...
   *|__________________________________________________
   */
  table fib {
    key = { m.hashtray : lpm; }
    
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
    bit<32> regindex;
    bit<HASHTRAY_LENGTH> associated_name;
    hash(regindex, HashAlgorithm.crc32, (Hash) 0, m.hashtray,
         (Hash) (REGISTER_ARRAY_SIZE-1));
    // Using a classic method of indexing into a hash table won't work.
    // Due to the way the hashtray is built, the rightmost bits are almost
    // always zeroes. Therefore, treating the hashtray as a big integer and
    // using modulo (analogue to using bit-AND on the rightmost bits) will
    // yield 0 practically everytime.

    
    
/* ============================================================================
 * --- PACKET TYPE:     N A K
 * ============================================================================
 * When a NAK is received from upstream, it will come as a response to a Data
 * packet. The network may be congestioned, or the router has no path for the
 * requested name, or some other reason. That reason should be indicated by a
 * field in the NAK packet.
 *
 * In this work, we decided that a NAK packet is a packet type by itself. Other
 * works in NDN may consider NAK packet to be a subtype of Data.
 *
 * Support for NAK is incomplete. No code exists to emit NAKs.
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
      PIT.read(m.mcastports, regindex);
      
      // NOTE: We do not check PITnames because we're assuming no Data will
      // arrive whose hashtray yields this index, though this ain't necessarily
      // true...

      //2ND: Add to the CS and clone to every output port.
      if (m.mcastports == 0) { //No ports requested this => spurious => drop

        Drop();

      } else {

        //--- a) add to the content store
        #ifdef CONTENT_STORE
        cache<bit<HASHTRAY_LENGTH>>(m.hashtray, 1);
        #endif


        //--- b) clean the pit entry
        PIT.write(regindex, 0);
        PITnames.write(regindex, 0);


        //--- c) mirror the Data packet to all requesting faces
        getNextFlaggedPort.apply();

      }
    }//NDNTYPE_DATA
       
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
#ifdef CONTENT_STORE
     
      //2ND: Check CS to see if we can serve directly
      if ( exists(m.hashtray) ) {

        //--- a) call to extern function that retrieves the packet
        retrieve(m.hashtray);
 
        //--- b) Swap input and output port, as well as ethernet addresses
        stdm.egress_spec = stdm.ingress_port;

        bit<48> temp = p.ethernet.srcAddr;
        p.ethernet.srcAddr = p.ethernet.dstAddr;
        p.ethernet.dstAddr = temp;

        //3RD: No entry in Content Store. Register nonce in PIT
      } else {
  
#endif // CONTENT_STORE       
        
        // Extract association in PIT index 'regindex'.
        PITnames.read(associated_name, regindex);
        
        
        // CASE A: 
        // Cell is freed => first Interest seen for this name
        // (this should be the most common case, so this if comes first)
        if (associated_name == 0) {
          
          // A.1 -- Consult the FIB
          switch (fib.apply().action_run) {
              Drop: { return; } //Forward if entry exists, otherwise Drop
              //return is necessary to avoid altering the PIT
              //TODO: Should send NAK packet towards ingress_port
          };
          
          // A.2 -- Store data in PIT
          PITnames.write(regindex, m.hashtray);
          PIT.write(regindex, 
              (bit<NUMBER_OF_PORTS>) 1 << ((bit<8>) stdm.ingress_port));
        
          
        // CASE B: 
        // Cell is already occupied with the same name as this Interest
        } else if (associated_name == m.hashtray) {
          
          // B.1 -- Retrieve the bit array already there
          PIT.read(m.mcastports, regindex);
          
          // B.2 -- BIT-OR the current array with the bit of this ingress_port
          // to memorize that it is also requesting the same name
          m.mcastports = m.mcastports | 
            ((bit<NUMBER_OF_PORTS>) 1 << ((bit<8>) stdm.ingress_port));
          
          // B.3 -- Store the result back in the PIT
          PIT.write(regindex, m.mcastports);
        
          
        // CASE C: 
        // PIT cell is occupied by another name => Drop. Consumer must try
        // again later, hopefully after the request which occupies this PIT
        // cell has already been served.
        } else {
          Drop();
        }
        
#ifdef CONTENT_STORE
      }
#endif
    }
  }
}

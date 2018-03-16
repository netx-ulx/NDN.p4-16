#include "defs.p4"

control TopEgress(inout Parsed_packet p, inout Metadata m, inout standard_metadata_t stdm) {
   
   #include "Actions.p4"
   
   /**
    * Set the source MAC address.
    * @param smac: Source MAC address to write onto the field.
   */
   action Set_smac(bit<48> smac)
   { p.ethernet.srcAddr = smac; }

   
   /**
    * Set the packet destination MAC address.
    * @param dmac: Destination MAC address to write onto the field.
   */ 
   action Set_dmac(bit<48> dmac)
   { p.ethernet.dstAddr = dmac; }
   
   
   /**
    * Set the source mac address based on the output port.
    * If the test environment does not define one, the default
    * should be to make the router invisible => NoAction()
    */
   table smac {
      
      key = {
         stdm.egress_port: exact;
      }

      actions = {
         NoAction;
         Set_smac;
      }

      size = NUMBER_OF_PORTS;
      default_action = NoAction(); //TO BE REVISED: Should be broadcast
   }
   
   
   /**
    * Set the destination mac address based on the output port.
    */
   table dmac {
      
      key = {
         stdm.egress_port: exact;
      }
           
      actions = {
         Drop;
         Set_dmac;
      }
        
      size = NUMBER_OF_PORTS;
      default_action = Drop();
   }
   
   
   /**
    * This action changes the metadata field "mcastports".
    * The difference between this action and the ingress version of it is that
    * the value of 'dist' is summed to stdm.egress_spec, so as to set the clone
    * on the right track.
    * 
    * TODO: WARNING: This assumes egress_spec is used to determine the egress
    * queue of the clone! Currently NOT a feature of BMv2 simple_switch.
    * TO BE REVISED.
    *
    * @param dist - Distance to the rightmost raised bit.
    */
   action ShiftToRightmostRaisedBit(bit<NUMBER_OF_PORTS_LOG> dist) { 
      stdm.egress_spec = stdm.egress_port + (bit<9>) dist + 1;
      m.mcastports = m.mcastports >> dist;
      clone3<Metadata>(CloneType.E2E, 1, m);
   }
   
   
   /**
    * Given the bit pattern in m.mcastports, the distance to the
    * rightmost raised/set bit (i.e. bit whose value is 1) is fetched from the
    * table entries. m.mcastports is shifted accordingly, and egress_spec
    * is incremented by the same amount.
    *
    * This is part of the multicast process. Each bit that is raised in
    * m.mcastports represents a port that awaits a copy of the Data we're
    * receiving.
    */
   table getNextFlaggedPort {
      
      key = { m.mcastports : ternary; }
      
      actions = {
         ShiftToRightmostRaisedBit;
         NoAction;
      }
      
      const default_action = NoAction;
      
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
     
   if (stdm.drop == 1)
      return;
   

   if (m.mcastports > 1) {
      m.mcastports = m.mcastports >> 1;
      getNextFlaggedPort.apply();
   }
     
   smac.apply();
   dmac.apply();
  }
}

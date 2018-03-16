#include "defs.p4"
#ifdef TARGET_BMV2
 #include "FixedLengthParser.p4"
#else
 #include "Parser.p4"
#endif
#include "Ingress.p4"
#include "Egress.p4"
#include "Deparser.p4"


/*
//These lines are uninteresting. We placed them here only for when we needed to
//replace the Parser block with a blank one.

parser InitialParser(packet_in b, out Parsed_packet p, inout Metadata m, inout standard_metadata_t standard_metadata) {
	
	state start {
		transition accept;
	}
}
*/

control VeryChecksum(inout Parsed_packet hdr, inout Metadata m) {
	apply { }
}

control ChecksumComputer(inout Parsed_packet hdr,
                              inout Metadata m) { apply {} }

/*
//These lines are uninteresting. We placed them here only for when we needed to
//replace the Ingress, Egress or Deparser blocks with blank ones.

control TopIngress(inout Parsed_packet p, inout Metadata m, inout standard_metadata_t standard_metadata) { apply{} }

control TopEgress(inout Parsed_packet p, inout Metadata m, inout standard_metadata_t standard_metadata) { apply{} }

control TopDeparser(packet_out b, in Parsed_packet p) { apply {} }
*/

V1Switch(InitialParser(), VeryChecksum(), TopIngress(), TopEgress(), ChecksumComputer(), TopDeparser()) main;

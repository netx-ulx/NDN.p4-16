#include <core.p4>


#define MAXIMUM_COMPONENTS	32
// Headerstacks require a limit a priori. Although the rest of this P4 program assumes an
// unbounded number of components, we have to define a limit for the header stack.

#define HASH_LENGTH 32	//length for a component's hash digest in BITS.
	//Results in more collisions (collision in the sense of two different objects
	//with the same hash) if smaller, increases tables' sizes if bigger.

#define TOTAL_HASHED_COMPONENTS_LENGTH 2048//( 64 * 32 ) //ALWAYS PLACE
//MAXIMUM_COMPONENTS * HASH_LENGTH HERE!! Compiler doesn't seem to wanna let us do that

#define NUMBER_OF_PORTS    16 //the number of ports of this device

#define MAXIMUM_TLV_SIZE 0x7fFFffFF /* ffFFffFF */
/* Maximum tolerated size for a TLV. This is a theoretical limit, but if the
 * protocol runs over Ethernet, it should be 1500 minus the size of an Ethernet
 * header, at most.
 * Adding extra makes the P4 compiler yell that it is too large a value.
 */

// Define for the encoding of the length of a TLV block
#define ENCODING_2BYTE     0xFD
#define ENCODING_4BYTE     0xFE
#define ENCODING_8BYTE     0xFF

// Define for ethertype and type codes
#define ETHERTYPE_NDN         0x8624 // code used by the NFD daemon
#define NDNTYPE_INTEREST      0x05
#define NDNTYPE_DATA          0x06
#define NDNTYPE_NAK           0x02


//Common fields
#define NDNTYPE_NAME          0x07
#define NDNTYPE_COMPONENT     0x08
#define NDNTYPE_SHA256DIGEST  0x01


//Interest packet
#define NDNTYPE_SELECTOR	  0x09
#define NDNTYPE_NONCE         0x0a
#define NDNTYPE_LINK          0x0b
#define NDNTYPE_LIFETIME	  0x0c
#define NDNTYPE_DELEGATION	  0x1e

//Interest/selectors
#define NDNTYPE_MINSUFFIX     0x0d
#define NDNTYPE_MAXSUFFIX     0x0e
#define NDNTYPE_PKEYLOCATOR   0x0f 
#define NDNTYPE_EXCLUDE	      0x10 
#define NDNTYPE_CHILDSELECTOR 0x11 
#define NDNTYPE_MUSTBEFRESH	  0x12 
#define NDNTYPE_KEYDIGEST	  0x1d 
#define NDNTYPE_ANY           0x13


//Data packet
#define NDNTYPE_METAINFO      0x14
#define NDNTYPE_CONTENT       0x15
#define NDNTYPE_SIGNATUREINFO 0x16
#define NDNTYPE_SIGNATUREVAL  0x17

//Data/metainfo
#define NDNTYPE_VTYPE         0x18
#define NDNTYPE_FRESHPERIOD   0x19
#define NDNTYPE_FINALBLOCKID  0x1a

//Data/Signature
#define NDNTYPE_SIGNATURETYPE 0x1b
#define NDNTYPE_KEYLOCATOR	  0x1c
#define NDNTYPE_KEYDIGEST	  0x1d


#define OP_NO_OP              0
#define OP_CLEAN_PIT_ENTRY    1
#define OP_UPDATE_FACE_LIST   2
#define OP_REFRESH_TIMEOUT    4



typedef bit<32>  P4DualExtractArg; //This field represents the maximum suported size, in bits, of a value assignment for a dynamic length of a varbit. P4's current extract() method maps this value to 32 bits, so 32 bits is the maximum allowed size.
typedef bit<TOTAL_HASHED_COMPONENTS_LENGTH> HashedCompsLength;
typedef bit<HASH_LENGTH> Hash;
typedef bit<32> Nonce;

struct TL_struct {
	//bit<8> type;
	bit<8> lencode;
	P4DualExtractArg size;
}

extern ContentStore<Pkt_t,Name_t> {
	ContentStore(bit<32> sizeInUnits);
	void archive(in Pkt_t packet);//Updates lifetime if already present
	bool exists(in Name_t name);
	void retrieve(in Name_t name,
				  out P4DualExtractArg totalsize,
				  //signature info
  				  out TL_struct signatureinfo,
				  out varbit<MAXIMUM_TLV_SIZE> signatureinfo_v,
				  //signature value
				  out TL_struct signaturevalue,
				  out varbit<MAXIMUM_TLV_SIZE> signaturevalue_v,
				  //metainfo
				  out TL_struct metainfo,
				  out varbit<MAXIMUM_TLV_SIZE> metainfo_v,
				  //content
				  out TL_struct content,
				  out varbit<MAXIMUM_TLV_SIZE> content_v);
}

extern PIT<Pkt_t,Name_t,Ports_t> {
	PIT(bit<32> size);
	bool register(in Name_t name, in Nonce nonce);//if name already exists, adds nonce. //Returns true in that case
	void mark_received(in Pkt_t packet);
	Ports_t getwnonce(in Name_t name, Nonce nonce);
	Ports_t get(in Name_t name);//a null result is a Parsed_packet with a tl0 whose type equals 0.
}

extern ComponentHashGenerator {
	//ComponentHashGenerator();
	bit<256> digest<D>(in D component, bit<8> length);
	//always returns a bit<256>, but only the least significant 2^length bits used.
}

//==========================================================
//==========================================================
/**
 * This parser should be responsible for interfacing between NDN and the link-layer
 * protocol being used. After transitioning to Accept, an unparsed 
 * @param <H> Parsed representation of the headers used by th

parser LinkLayerInterfaceParser<H>(packet_in b, inout H parsedHeaders); */

/**
 * A programmable parser. A parser is responsible for identifying the type of packet
 * we're dealing with.
 * @param <H> Parsed representation of the packet.
 * @param b Input stream of octets to be interpreted by the parser. Set automatically when
 * the parser is summoned.
 * @param parsedHeaders Parsed representation that is filled by the parser.
 */
parser Parser<H>(packet_in b, inout H parsedHeaders);


/**
 * Match-action pipeline
 * @param <H> type of input and output headers
 * @param headers headers received from the parser and sent to the deparser
 * @param parseError error that may have surfaced during parsing
 * @param inCtrl information from architecture, accompanying input packet
 * @param outCtrl information for architecture, accompanying output packet
 */
control Pipe<H>(inout H headers,
                in error parseError,// parser error
                in InControl inCtrl,// input port
                out OutControl outCtrl); // output port

/**
 * Control block responsible for dealing with the fragmentation of NDN packets.
 * @param <H> Parsed representation of the packet.
 * @param headers Parsed representation as received by the Parser.
 */
control FragmentationHandler<H>(inout H headers);


/**
 * Switch deparser.
 * @param <H> type of headers; defined by user
 * @param b output packet
 * @param outputHeaders headers for output packet
 */
control Deparser<H>(inout H outputHeaders,
                    packet_out b);

/**
 * Top-level package declaration instantiated by the user.
 * @param <H> Structure that is the parsed representation of the packet.
 */
package NDNRouter<H>(Parser<H> p,
					 Pipe<H> processingPipeline,
					 FragmentationHandler<H> f,
					 Deparser<H> d);

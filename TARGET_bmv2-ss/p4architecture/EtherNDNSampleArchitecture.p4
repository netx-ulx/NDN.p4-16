//@file EthernetNDNSampleArchitecture.p4

/** 
 * This file is essentially an extension of the v1model architecture, since
 * it includes v1model.p4 and adds a few extra extern primitives.
 *
 * It also defines information that any device will have to provide, such as
 * the number of ports.
 *
 * Our complete program parses an unbounded number of components, but
 * P4 header stack constructs demand to know their size a priori, at
 * compile time. Later on, we built the FIB entries by relying on it as well.
 */

#ifndef _ETHER_NDN_SAMPLE_
#define _ETHER_NDN_SAMPLE_

#include "./v1model.p4"
#include "../p4include/NDNCore.p4"


#define MTU 1500 //maximum transmission unit for Ethernet


#define NUMBER_OF_PORTS_LOG 4 // The p4 compiler does not accept expressions
#define NUMBER_OF_PORTS 16 //the number of ports of this device

#define MAXIMUM_COMPONENTS_LOG 4
#define MAXIMUM_COMPONENTS 16 
// Headerstacks require a limit a priori. Our program can parse an unbounded
// number of components, but we have to define a limit for the header stack.

#define CPU_MIRROR_SESSION_ID 250


/**
 * Archives the packet in the Content Store.
 *
 * @param <K> - Type of the key. Usually bit of some length.
 * @param packet - Packet instance to be archived.
 * @param key - The key that identifies the packet.
 * @param refresh - Indicator that, because the packet was recently
 * requested, the Content Store should attempt to hold on to it.
 * 1 for yes, 0 for no.
 */
extern void cache<K>(in K key, bit<1> refresh);


/**
 * Checks if a packet identified by this key exists in the Content Store.
 *
 * @param <K> - Type of the key. It should be a hash.
 * @param key - Key that uniquely identifies the packet.
 * 
 * @return true if a packet with this key exists in the cache.
 */
extern bool exists<K>(in K key);


/**
 * Immediately replaces the packet buffer content with that of the
 * archived packet according to the key. Keeps metadata intact.
 *
 * @param <K> - Type of the key. It should be a hash.
 * @param key - Key that uniquely identifies the packet.
 * @param <C> - The type of the content.
 * @param content - The content we wish to retrieve.
 */
extern void retrieve<K>(in K key);


#endif // _ETHER_NDN_SAMPLE_

//#include <cassert>
//#include <ctime>

//#include <string>
#include <stdio.h>
//#include <sys/time.h>

#include "cs.h"

#define BITS_FOR_COMPONENTS 128

//=============================================================================

  std::string ExternContentStore::findReplacement() {

	for (auto it : cache) {
		return it.first;
	}
 	return 0;
  }

  ExternContentStore::ExternContentStore(unsigned short max_packets /*= 0*/) {
	attr_maxpkts = max_packets > 0 ? max_packets : CS_MAX_PACKETS;
  }

  
  void ExternContentStore::store(const Field &hash, const Field &content, const Field &freshness)
  {
	std::string key = hash.get_string();
	const auto itr = cache.find(key);

	if (attr_size >= attr_maxpkts) {
		
		std::string cell_being_replaced = findReplacement();

		//Get the pointer stored in the map
		PacketCell * c = cache[cell_being_replaced];

		//Delete pointer from the map (leaves the object intact)
		cache.erase(cell_being_replaced);
		
		//Change our cell to insert new data
		c->set(content, freshness);

		//Reinsert into the map with a different key
		cache[key] = c;

	} else if (itr == cache.end()) {
		PacketCell * newcell = new PacketCell(content, freshness);
		cache.insert( {key, newcell} );
		++attr_size;
	} else {
		cache.at(key)->set(content, freshness);
	}
  }



  // Sets the fields to the stored values. Assumes they are contained by
  // a valid hdr and that the requested hash exists
  void ExternContentStore::retrieve(const Field &hash, Field &content, Field &freshness) const {
	PacketCell * c = cache.at(hash.get_string());

	content.set(c->getContent());
	freshness.set(c->getFreshnessPeriod());
  }


  Data& ExternContentStore::getContent(const Field &hash) {
	return cache[hash.get_string()]->getContent();
  }

  Data& ExternContentStore::getFreshness(const Field &hash) {
	return cache[hash.get_string()]->getFreshnessPeriod();
  }


  bool ExternContentStore::contains(const Field &hash) const {
	return cache.find(hash.get_string()) != cache.end();
  }
//class ExternContentStore

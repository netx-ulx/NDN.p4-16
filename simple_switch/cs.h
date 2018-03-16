
#ifndef _CS_H_
#define _CS_H_


#include <bm/bm_sim/extern.h>
#include <bm/bm_sim/P4Objects.h>
//#include <bm/bm_sim/data.h>
//#include <bm/bm_sim/field.h>

#include <map>
#include <string>
#include <iostream>
#include <fstream>
#include <unistd.h>

using bm::Data;
using bm::Field;

namespace ruiss {

class PacketCell {

 public:
	
	//Empty constructor
	explicit PacketCell() {
		attr_freshness = new Data();
		attr_content = new Data();
		attr_filled = false;
	}

	explicit PacketCell(const Data &c, const Data &freshness) {
		attr_freshness = new Data(freshness);
		attr_content = new Data(c);
		attr_filled = true;
	}


	void set(const Data &content, const Data &freshness)
	{
		attr_content->set(content);
		attr_freshness->set(freshness);
		attr_filled = true;
	}


	void updateFreshness(const Data &freshness) {
		attr_freshness->set(freshness);
	}


	Data& getFreshnessPeriod()
	{ return *attr_freshness; }

	Data& getContent()
	{ return *attr_content; }

	bool isFilled() const
	{ return attr_filled; }

	
 private:
	//implementation members
	Data * attr_freshness;
	Data * attr_content;
	//Data * attr_hash;
	bool attr_filled;
};
}//namespace



using ruiss::PacketCell;

//class SimpleSwitch : public Switch {
class ExternContentStore {


public:

  static constexpr unsigned int CS_MAX_STORED_PACKETS_LOG = 9; //9 here yields 512 packets
  static constexpr unsigned int CS_MAX_PACKETS = 1 << CS_MAX_STORED_PACKETS_LOG;

  ExternContentStore(unsigned short max_packets = 0);

  void store(const Field &hash, const Field &content, const Field &freshness);

  void retrieve(const Field &hash, Field &content, Field &freshness) const;

  bool contains(const Field &hash) const;

  Data& getContent(const Field &hash);

  Data& getFreshness(const Field &hash);

  ~ExternContentStore();

private:
	unsigned int attr_maxpkts;
	unsigned int attr_size;
	std::unordered_map< std::string, PacketCell *> cache;

        std::string findReplacement();
};

#endif //_CS_H_

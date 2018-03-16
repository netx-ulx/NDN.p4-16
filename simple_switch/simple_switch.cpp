/* Copyright 2013-present Barefoot Networks, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * Antonin Bas (antonin@barefootnetworks.com)
 * altered by Rui Miguel (@LASIGE DI-FCUL)
 */

#include <bm/bm_sim/parser.h>
#include <bm/bm_sim/tables.h>
#include <bm/bm_sim/logger.h>

#include <unistd.h>

#include <iostream>
#include <fstream>
#include <string>

#include "simple_switch.h"

namespace {

struct hash_ex {
  uint32_t operator()(const char *buf, size_t s) const {
    const uint32_t p = 16777619;
    uint32_t hash = 2166136261;

    for (size_t i = 0; i < s; i++)
      hash = (hash ^ buf[i]) * p;

    hash += hash << 13;
    hash ^= hash >> 7;
    hash += hash << 3;
    hash ^= hash >> 17;
    hash += hash << 5;
    return static_cast<uint32_t>(hash);
  }
};

struct bmv2_hash {
  uint64_t operator()(const char *buf, size_t s) const {
    return bm::hash::xxh64(buf, s);
  }
};

}  // namespace

// if REGISTER_HASH calls placed in the anonymous namespace, some compiler can
// give an unused variable warning
REGISTER_HASH(hash_ex);
REGISTER_HASH(bmv2_hash);

extern int import_primitives();

SimpleSwitch::SimpleSwitch(int max_port, bool enable_swap)
  : Switch(enable_swap),
    max_port(max_port),
    input_buffer(1024),
#ifdef SSWITCH_PRIORITY_QUEUEING_ON
    egress_buffers(max_port, nb_egress_threads,
                   64, EgressThreadMapper(nb_egress_threads),
                   SSWITCH_PRIORITY_QUEUEING_NB_QUEUES),
#else
    egress_buffers(max_port, nb_egress_threads,
                   64, EgressThreadMapper(nb_egress_threads)),
#endif
    output_buffer(128),
    pre(new McSimplePreLAG()),
    start(clock::now()) {
  cs = new ExternContentStore();
  add_component<McSimplePreLAG>(pre);

  add_required_field("standard_metadata", "ingress_port");
  add_required_field("standard_metadata", "packet_length");
  add_required_field("standard_metadata", "instance_type");
  add_required_field("standard_metadata", "egress_spec");
  add_required_field("standard_metadata", "clone_spec");
  add_required_field("standard_metadata", "egress_port");

  force_arith_field("standard_metadata", "ingress_port");
  force_arith_field("standard_metadata", "packet_length");
  force_arith_field("standard_metadata", "instance_type");
  force_arith_field("standard_metadata", "egress_spec");
  force_arith_field("standard_metadata", "clone_spec");

  force_arith_field("queueing_metadata", "enq_timestamp");
  force_arith_field("queueing_metadata", "enq_qdepth");
  force_arith_field("queueing_metadata", "deq_timedelta");
  force_arith_field("queueing_metadata", "deq_qdepth");

  force_arith_field("intrinsic_metadata", "ingress_global_timestamp");
  force_arith_field("intrinsic_metadata", "lf_field_list");
  force_arith_field("intrinsic_metadata", "mcast_grp");
  force_arith_field("intrinsic_metadata", "resubmit_flag");
  force_arith_field("intrinsic_metadata", "egress_rid");
  force_arith_field("intrinsic_metadata", "recirculate_flag");

  force_arith_header("content");

  import_primitives();
}

#define PACKET_LENGTH_REG_IDX 0

int
SimpleSwitch::receive_(int port_num, const char *buffer, int len) {
  static int pkt_id = 0;

  // this is a good place to call this, because blocking this thread will not
  // block the processing of existing packet instances, which is a requirement
  if (do_swap() == 0) {
    check_queueing_metadata();
  }

  // we limit the packet buffer to original size + 512 bytes, which means we
  // cannot add more than 512 bytes of header data to the packet, which should
  // be more than enough
  auto packet = new_packet_ptr(port_num, pkt_id++, len,
                               bm::PacketBuffer(len + 512, buffer, len));

  BMELOG(packet_in, *packet);

  PHV *phv = packet->get_phv();
  // many current P4 programs assume this
  // it is also part of the original P4 spec
  phv->reset_metadata();

  // setting standard metadata

  phv->get_field("standard_metadata.ingress_port").set(port_num);
  // using packet register 0 to store length, this register will be updated for
  // each add_header / remove_header primitive call
  packet->set_register(PACKET_LENGTH_REG_IDX, len);
  phv->get_field("standard_metadata.packet_length").set(len);
  Field &f_instance_type = phv->get_field("standard_metadata.instance_type");
  f_instance_type.set(PKT_INSTANCE_TYPE_NORMAL);

  if (phv->has_field("intrinsic_metadata.ingress_global_timestamp")) {
    phv->get_field("intrinsic_metadata.ingress_global_timestamp")
        .set(get_ts().count());
  }

  input_buffer.push_front(std::move(packet));
  return 0;
}

void
SimpleSwitch::start_and_return_() {
  check_queueing_metadata();

  std::thread t1(&SimpleSwitch::ingress_thread, this);
  t1.detach();
  for (size_t i = 0; i < nb_egress_threads; i++) {
    std::thread t2(&SimpleSwitch::egress_thread, this, i);
    t2.detach();
  }
  std::thread t3(&SimpleSwitch::transmit_thread, this);
  t3.detach();
}

void
SimpleSwitch::reset_target_state_() {
  bm::Logger::get()->debug("Resetting simple_switch target-specific state");
  get_component<McSimplePreLAG>()->reset_state();
}

int
SimpleSwitch::set_egress_queue_depth(int port, const size_t depth_pkts) {
  egress_buffers.set_capacity(port, depth_pkts);
  return 0;
}

int
SimpleSwitch::set_all_egress_queue_depths(const size_t depth_pkts) {
  for (int i = 0; i < max_port; i++) {
    set_egress_queue_depth(i, depth_pkts);
  }
  return 0;
}

int
SimpleSwitch::set_egress_queue_rate(int port, const uint64_t rate_pps) {
  egress_buffers.set_rate(port, rate_pps);
  return 0;
}

int
SimpleSwitch::set_all_egress_queue_rates(const uint64_t rate_pps) {
  for (int i = 0; i < max_port; i++) {
    set_egress_queue_rate(i, rate_pps);
  }
  return 0;
}

uint64_t
SimpleSwitch::get_time_elapsed_us() const {
  return get_ts().count();
}

uint64_t
SimpleSwitch::get_time_since_epoch_us() const {
  auto tp = clock::now();
  return duration_cast<ts_res>(tp.time_since_epoch()).count();
}

void
SimpleSwitch::transmit_thread() {
  while (1) {
    std::unique_ptr<Packet> packet;
    output_buffer.pop_back(&packet);
    BMELOG(packet_out, *packet);
    BMLOG_DEBUG_PKT(*packet, "Transmitting packet of size {} out of port {}",
                    packet->get_data_size(), packet->get_egress_port());
    transmit_fn(packet->get_egress_port(),
                packet->data(), packet->get_data_size());
  }
}

ts_res
SimpleSwitch::get_ts() const {
  return duration_cast<ts_res>(clock::now() - start);
}

void
SimpleSwitch::enqueue(int egress_port, std::unique_ptr<Packet> &&packet) {
    packet->set_egress_port(egress_port);

    PHV *phv = packet->get_phv();

    if (with_queueing_metadata) {
      phv->get_field("queueing_metadata.enq_timestamp").set(get_ts().count());
      phv->get_field("queueing_metadata.enq_qdepth")
          .set(egress_buffers.size(egress_port));
    }

#ifdef SSWITCH_PRIORITY_QUEUEING_ON
    size_t priority = phv->has_field(SSWITCH_PRIORITY_QUEUEING_SRC) ?
        phv->get_field(SSWITCH_PRIORITY_QUEUEING_SRC).get<size_t>() : 0u;
    if (priority >= SSWITCH_PRIORITY_QUEUEING_NB_QUEUES) {
      bm::Logger::get()->error("Priority out of range, dropping packet");
      return;
    }
    egress_buffers.push_front(
        egress_port, SSWITCH_PRIORITY_QUEUEING_NB_QUEUES - 1 - priority,
        std::move(packet));
#else
    egress_buffers.push_front(egress_port, std::move(packet));
#endif
}

// used for ingress cloning, resubmit
std::unique_ptr<Packet>
SimpleSwitch::copy_ingress_pkt(
    const std::unique_ptr<Packet> &packet,
    PktInstanceType copy_type, p4object_id_t field_list_id) {
  std::unique_ptr<Packet> packet_copy = packet->clone_no_phv_ptr();
  PHV *phv_copy = packet_copy->get_phv();
  phv_copy->reset_metadata();
  FieldList *field_list = this->get_field_list(field_list_id);
  field_list->copy_fields_between_phvs(phv_copy, packet->get_phv());
  phv_copy->get_field("standard_metadata.instance_type").set(copy_type);
  return packet_copy;
}

void
SimpleSwitch::check_queueing_metadata() {
  bool enq_timestamp_e = field_exists("queueing_metadata", "enq_timestamp");
  bool enq_qdepth_e = field_exists("queueing_metadata", "enq_qdepth");
  bool deq_timedelta_e = field_exists("queueing_metadata", "deq_timedelta");
  bool deq_qdepth_e = field_exists("queueing_metadata", "deq_qdepth");
  if (enq_timestamp_e || enq_qdepth_e || deq_timedelta_e || deq_qdepth_e) {
    if (enq_timestamp_e && enq_qdepth_e && deq_timedelta_e && deq_qdepth_e)
      with_queueing_metadata = true;
    else
      bm::Logger::get()->warn(
          "Your JSON input defines some but not all queueing metadata fields");
  }
}

void
SimpleSwitch::ingress_thread() {
  PHV *phv;

  while (1) {
    std::unique_ptr<Packet> packet;
    input_buffer.pop_back(&packet);

    // TODO(antonin): only update these if swapping actually happened?
    Parser *parser = this->get_parser("parser");
    Pipeline *ingress_mau = this->get_pipeline("ingress");

    phv = packet->get_phv();

    int ingress_port = packet->get_ingress_port();
    (void) ingress_port;
    BMLOG_DEBUG_PKT(*packet, "Processing packet received on port {}",
                    ingress_port);

    /* This looks like it comes out of the blue. However this is needed for
       ingress cloning. The parser updates the buffer state (pops the parsed
       headers) to make the deparser's job easier (the same buffer is
       re-used). But for ingress cloning, the original packet is needed. This
       kind of looks hacky though. Maybe a better solution would be to have the
       parser leave the buffer unchanged, and move the pop logic to the
       deparser. TODO? */
    const Packet::buffer_state_t packet_in_state = packet->save_buffer_state();
    parser->parse(packet.get());

    ingress_mau->apply(packet.get());

    packet->reset_exit();

  //========================= RUI'S BULK OF CODE STARTS HERE ==================
  //This huge bulk of code could be smaller without the ifs, but it is just to
  //make sure the switch doesn't crash when the fields aren't present (calls to
  //phv->get_field() will have that result if the field doesn't exist).
  //--------------------
  //The code below caches Data packets when one is received (to determine if it
  //is Data, it checks the presence of a Content header, and not type, though).
    if (phv->has_field("scalars.Metadata.cloning_to_ports") &&
	phv->has_field("scalars.Metadata.hashed_components") &&
	phv->has_field("content.value"))
    {

      if (phv->get_field("scalars.Metadata.cloning_to_ports").get_uint64() > 0)
      {
        const Field &f_hash = phv->get_field("scalars.Metadata.hashed_components");
        const Field &f_content = phv->get_field("content.value");
        const Field &f_freshness = phv->get_field("freshnessPeriod.value");

        BMLOG_DEBUG_PKT(*packet, "Caching Data packet");
        cs->store(f_hash, f_content, f_freshness);
      }
    }

    const bool HAS_FRESHNESS = false;

    //This code replaces an Interest's headers for those of Data.
    //It also swaps addresses and ingress/egress ports, effectively
    //sending the packet backwards
    if (phv->has_field("scalars.Metadata.hashed_components") &&
	phv->has_field("scalars.Metadata.NDNpkttype") &&
	phv->has_field("tl0.type") &&
	phv->has_header("nonce") &&
	phv->has_header("content"))
    {
      if (phv->get_field("scalars.Metadata.NDNpkttype").get_uint() == 0x05)
      //NDNTYPE_INTEREST
      {
        Field &f_hash = phv->get_field("scalars.Metadata.hashed_components");

        BMLOG_DEBUG_PKT(*packet, "Checking Content Store for Data.");

        if (cs->contains(f_hash)) {
          BMLOG_DEBUG_PKT(*packet, "Data in cache exists to satisfy Interest. Replacing fields now");
          Data &f_content = cs->getContent(f_hash);
          Data &f_freshness = cs->getFreshness(f_hash);

          BMLOG_DEBUG_PKT(*packet, "Attempting to access PIT registers to overwrite set ports");

          Data &f_tl0len = phv->get_field("tl0.lencode");

          //TL0
          phv->get_field("tl0.type").set(0x06);

          uint64_t len = f_tl0len.get_uint64();
	  len = len - 6 + 8 + 2; //nonce, content.value and content type & len
          f_tl0len.set(len);

          
          //HEADERS
          phv->get_header("nonce").mark_invalid();
          phv->get_header("content").reset();
          phv->get_header("content").mark_valid();//Will not work casually if changed
          //BMv2 does a number of optimizations which locks arithmetic for unused
          //fields. See line 110
          packet->set_register(0, packet->get_register(0) - phv->get_header("nonce").get_nbytes_packet());
          packet->set_register(0, packet->get_register(0) + phv->get_header("content").get_nbytes_packet());

          //Content
          phv->get_header("content").get_field(0).set(0x15);

          Field &f_content_lencode = phv->get_header("content").get_field(1);
          f_content_lencode.set(8);

          phv->get_field("content.value").set(f_content);

          //Freshness
          if (HAS_FRESHNESS) {
            Field &f_freshness_lencode = phv->get_field("freshnessPeriod.lencode");
            len =  f_freshness_lencode.get_uint64() + 8 + 2;
            f_tl0len.set(len);

            phv->get_header("freshnessPeriod").mark_valid();
            phv->get_field("freshnessPeriod.type").set(0x19);
            phv->get_field("freshnessPeriod.value").set(f_freshness);
          }

          //Swap ports
          phv->get_field("standard_metadata.egress_spec").set(
		phv->get_field("standard_metadata.ingress_port"));

          //Ethernet 
          Field &f_eth_srcAddr = phv->get_field("ethernet.srcAddr");
          const uint64_t temp = f_eth_srcAddr.get_uint64();
          f_eth_srcAddr.set(phv->get_field("ethernet.dstAddr"));
          phv->get_field("ethernet.dstAddr").set(temp);
        }

      }
    }
  //========================== RUI'S BULK OF CODE ENDS HERE ===========================

    Field &f_egress_spec = phv->get_field("standard_metadata.egress_spec");
    int egress_spec = f_egress_spec.get_int();

  //========================= RUI'S BULK OF CODE STARTS HERE ==========================
  //This part of the code shifts the port array and sets the egress spec correctly
  //for the first packet.
    if (phv->has_field("scalars.Metadata.cloning_to_ports")) {
      Field &mcast = phv->get_field("scalars.Metadata.cloning_to_ports");
      uint64_t port_bit_vector = mcast.get_uint64();
      unsigned short i = 1;

      if (port_bit_vector > 0) {
        while ((port_bit_vector & 1) == 0) {
          port_bit_vector >>= 1;
          ++i;
        }

        //We shift one extra time. If a single bit was set, cloning_to_ports
        //becomes 0 and no cloning occurs.
        mcast.set(port_bit_vector >> 1);
        egress_spec = i;
      }
    }

  //========================== RUI'S CODE ENDS HERE ===========================

    Field &f_clone_spec = phv->get_field("standard_metadata.clone_spec");
    unsigned int clone_spec = f_clone_spec.get_uint();


    int learn_id = 0;
    unsigned int mgid = 0u;

    if (phv->has_field("intrinsic_metadata.lf_field_list")) {
      Field &f_learn_id = phv->get_field("intrinsic_metadata.lf_field_list");
      learn_id = f_learn_id.get_int();
    }

    // detect mcast support, if this is true we assume that other fields needed
    // for mcast are also defined
    if (phv->has_field("intrinsic_metadata.mcast_grp")) {
      Field &f_mgid = phv->get_field("intrinsic_metadata.mcast_grp");
      mgid = f_mgid.get_uint();
    }

    int egress_port;

    // INGRESS CLONING
    if (clone_spec) {
      BMLOG_DEBUG_PKT(*packet, "Cloning packet at ingress");
      egress_port = get_mirroring_mapping(clone_spec & 0xFFFF);
      f_clone_spec.set(0);
      if (egress_port >= 0) {
        const Packet::buffer_state_t packet_out_state =
            packet->save_buffer_state();
        packet->restore_buffer_state(packet_in_state);
        p4object_id_t field_list_id = clone_spec >> 16;
        auto packet_copy = copy_ingress_pkt(
            packet, PKT_INSTANCE_TYPE_INGRESS_CLONE, field_list_id);
        // we need to parse again
        // the alternative would be to pay the (huge) price of PHV copy for
        // every ingress packet
        parser->parse(packet_copy.get());
        enqueue(egress_port, std::move(packet_copy));
        packet->restore_buffer_state(packet_out_state);
      }
    }

    // LEARNING
    if (learn_id > 0) {
      get_learn_engine()->learn(learn_id, *packet.get());
    }

    // RESUBMIT
    if (phv->has_field("intrinsic_metadata.resubmit_flag")) {
      Field &f_resubmit = phv->get_field("intrinsic_metadata.resubmit_flag");
      if (f_resubmit.get_int()) {
        BMLOG_DEBUG_PKT(*packet, "Resubmitting packet");
        // get the packet ready for being parsed again at the beginning of
        // ingress
        packet->restore_buffer_state(packet_in_state);
        p4object_id_t field_list_id = f_resubmit.get_int();
        f_resubmit.set(0);
        // TODO(antonin): a copy is not needed here, but I don't yet have an
        // optimized way of doing this
        auto packet_copy = copy_ingress_pkt(
            packet, PKT_INSTANCE_TYPE_RESUBMIT, field_list_id);
        input_buffer.push_front(std::move(packet_copy));
        continue;
      }
    }

    Field &f_instance_type = phv->get_field("standard_metadata.instance_type");

    // MULTICAST
    int instance_type = f_instance_type.get_int();
    if (mgid != 0) {
      BMLOG_DEBUG_PKT(*packet, "Multicast requested for packet");
      Field &f_rid = phv->get_field("intrinsic_metadata.egress_rid");
      const auto pre_out = pre->replicate({mgid});
      auto packet_size = packet->get_register(PACKET_LENGTH_REG_IDX);
      for (const auto &out : pre_out) {
        egress_port = out.egress_port;
        // if (ingress_port == egress_port) continue; // pruning
        BMLOG_DEBUG_PKT(*packet, "Replicating packet on port {}", egress_port);
        f_rid.set(out.rid);
        f_instance_type.set(PKT_INSTANCE_TYPE_REPLICATION);
        std::unique_ptr<Packet> packet_copy = packet->clone_with_phv_ptr();
        packet_copy->set_register(PACKET_LENGTH_REG_IDX, packet_size);
        enqueue(egress_port, std::move(packet_copy));
      }
      f_instance_type.set(instance_type);

      // when doing multicast, we discard the original packet
      continue;
    }

    egress_port = egress_spec;
    BMLOG_DEBUG_PKT(*packet, "Egress port is {}", egress_port);

    if (egress_port == 511) {  // drop packet
      BMLOG_DEBUG_PKT(*packet, "Dropping packet at the end of ingress");
      continue;
    }

    enqueue(egress_port, std::move(packet));
  }
}

void
SimpleSwitch::egress_thread(size_t worker_id) {
  PHV *phv;

  while (1) {
    std::unique_ptr<Packet> packet;
    size_t port;
    egress_buffers.pop_back(worker_id, &port, &packet);

    Deparser *deparser = this->get_deparser("deparser");
    Pipeline *egress_mau = this->get_pipeline("egress");

    phv = packet->get_phv();

    if (with_queueing_metadata) {
      auto enq_timestamp =
          phv->get_field("queueing_metadata.enq_timestamp").get<ts_res::rep>();
      phv->get_field("queueing_metadata.deq_timedelta").set(
          get_ts().count() - enq_timestamp);
      phv->get_field("queueing_metadata.deq_qdepth").set(
          egress_buffers.size(port));
    }

    Field &f_egress_port = phv->get_field("standard_metadata.egress_port");
    f_egress_port.set(port);
    //unsigned int egress_port = f_egress_port.get_uint();

    Field &f_egress_spec = phv->get_field("standard_metadata.egress_spec");
    f_egress_spec.set(0);

    phv->get_field("standard_metadata.packet_length").set(
        packet->get_register(PACKET_LENGTH_REG_IDX));

    //############ APPLICATION OF THE EGRESS PIPELINE ################
    egress_mau->apply(packet.get());
    //############ APPLICATION OF THE EGRESS PIPELINE ################


    Field &f_clone_spec = phv->get_field("standard_metadata.clone_spec");
    const unsigned int clone_spec = f_clone_spec.get_uint();

    int egress_spec = f_egress_spec.get_int();//May have changed since egress spec was set to 0

    // EGRESS CLONING
    if (clone_spec) {
      BMLOG_DEBUG_PKT(*packet, "Primitive clone() has been invoked.");
      //int egress_port = get_mirroring_mapping(clone_spec & 0xFFFF);
      //if (egress_port >= 0) {
      f_clone_spec.set(0);
      p4object_id_t field_list_id = clone_spec >> 16;

      // ==================  RUI'S BULK OF CODE STARTS HERE ====================
      if (phv->has_field("scalars.Metadata.cloning_to_ports")) {

        BMLOG_DEBUG_PKT(*packet, "Found cloning_to_ports field on Metadata struct.");

        Field &mcast = phv->get_field("scalars.Metadata.cloning_to_ports");

        const unsigned short num_of_ports = mcast.get_nbits();
        unsigned long long port_bit_vector = mcast.get_uint64();
        unsigned short i = port + 1;

        mcast.set(0);

        BMLOG_DEBUG_PKT(*packet, "This device has {} ports", num_of_ports);
        BMLOG_DEBUG_PKT(*packet, "Value of cloning_to_ports is {}", port_bit_vector);

        if (port_bit_vector > 0)
        {
          for ( ; i < num_of_ports && port_bit_vector > 0 ; ++i){

           if ((port_bit_vector & 1) > 0) {
            BMLOG_DEBUG_PKT(*packet, "Cloning packet at egress to port {}", i);
      // ==================  RUI'S BULK OF CODE ENDS HERE ======================
            std::unique_ptr<Packet> packet_copy =
                packet->clone_with_phv_reset_metadata_ptr();
            PHV *phv_copy = packet_copy->get_phv();
            FieldList *field_list = this->get_field_list(field_list_id);
            field_list->copy_fields_between_phvs(phv_copy, phv);
            phv_copy->get_field("standard_metadata.instance_type")
                .set(PKT_INSTANCE_TYPE_EGRESS_CLONE);
            //enqueue(egress_spec, std::move(packet_copy));
            enqueue(i, std::move(packet_copy));
           }

           port_bit_vector >>= 1;
          }//for cycle
        }//(port_bit_vector > 0)
      } //(phv->has_field("scalars.Metadata.cloning_to_ports"))
      //}
    }

    // TODO(antonin): should not be done like this in egress pipeline
    //int egress_spec = f_egress_spec.get_int();
    if (egress_spec == 511) {  // drop packet
      BMLOG_DEBUG_PKT(*packet, "Dropping packet at the end of egress");
      continue;
    }

    deparser->deparse(packet.get());

    // RECIRCULATE
    if (phv->has_field("intrinsic_metadata.recirculate_flag")) {
      Field &f_recirc = phv->get_field("intrinsic_metadata.recirculate_flag");
      if (f_recirc.get_int()) {
        BMLOG_DEBUG_PKT(*packet, "Recirculating packet");
        p4object_id_t field_list_id = f_recirc.get_int();
        f_recirc.set(0);
        FieldList *field_list = this->get_field_list(field_list_id);
        // TODO(antonin): just like for resubmit, there is no need for a copy
        // here, but it is more convenient for this first prototype
        std::unique_ptr<Packet> packet_copy = packet->clone_no_phv_ptr();
        PHV *phv_copy = packet_copy->get_phv();
        phv_copy->reset_metadata();
        field_list->copy_fields_between_phvs(phv_copy, phv);
        phv_copy->get_field("standard_metadata.instance_type")
            .set(PKT_INSTANCE_TYPE_RECIRC);
        size_t packet_size = packet_copy->get_data_size();
        packet_copy->set_register(PACKET_LENGTH_REG_IDX, packet_size);
        phv_copy->get_field("standard_metadata.packet_length").set(packet_size);
        input_buffer.push_front(std::move(packet_copy));
        continue;
      }
    }

    output_buffer.push_front(std::move(packet));
  }
}

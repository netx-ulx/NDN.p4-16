# rawpkt

This folder contains all source code of the auxiliary program I developed, the NDN packet generator called **rawpkt**. This binary produces NDN packets on top of an Ethernet header.

## Command line arguments

Command line arguments were described in the master's dissertation report. We list them here for easy perusal:

* `-i <intf>` sets the outgoing interface for this packet. Default is eth0.
* `-c <num>` sets the number of packets to _num_. Default is 1.
* `-t <usecs>` or `--time <usecs>` sets the interval between packets in microseconds (10<sup>-6</sup>). We use `usleep()` to wait between emission periods. Default is 0.
* `-n <name>` to set the name. Eg: "abcdefgh/ihjklmno". WARNING: Because of BMv2's limitations, all name components must be 8 characters, and names must be no more than 4 components long. The default name is "portugal/unlisboa/fciencia/index.ht".
* `-f <filepath>` sets the packet type to *Data* and appends the contents of a given file. WARNING: Because of BMv2's limitations, the file must inhold exactly 8 bytes of content.
* `-d <dmac>` or `-deth <dmac>` sets the destination MAC address. Default is 00:01:00:00:00:01 if the host is 00:01:00:00:00:00, or 00:01:00:00:00:00 if the host is 00:01:00:00:00:01. Undefined when neither is the case.


## Items

* **defs.h** contains function and macro declarations.
* **rawpkt.c** contains the main() function.
* **cmd\_interpret.c** is the module of the program that interprets command line arguments.
* **ndn\_pkt\_building\_utils.c** defines the functions that build the NDN packet.
* **readpktfile.c** defines functions related to the `-f` command for file processing.

A makefile is also available, so you can simply write `make` in the terminal to compile rawpkt.


## Result

Using `make` outputs a binary called `rawpkt`. Using `rawpkt [options]`, on the absence of errors, emits one or more NDN packets.

# NDN.p4-16

This repository contains the source code for "_Named Data Networking using Programmable Switches_", a master's dissertation by Rui Miguel and supervised by Fernando Ramos, both from the Faculty of Sciences ("FCiências") of the University of Lisbon ("ULisboa").

## Introduction

My master's thesis applies the novel language P4 to the context of named data networks (NDN). P4 is a high-level language to program a forwarding device which provides a compiler for it. Such a device is said to **support P4** and is also called **P4-compatible**. Since switching hardware has only recently become programmable, possibilities are still limited, and only a handful support P4.

NDN is a brand new network architecture severed completely from the paradigm of TCP/IP and tailored for distribution. Lixia Zhang's 2014 paper is primary background for this work.

Because NDN routers manage state, IP equipment cannot be extended to support NDN functionality. My dissertation is a study of the challenges and quirks of programming a P4 switch — concretely, the Behavioral Model 2 simple\_switch, a virtual, software switch — with the functionality of the NDN router. This repository hosts all the resulting code, including that of auxiliary tools.

It is recommended that the interested visitor acquires background in each of these two areas before attempting to peruse the contents of this repository, as they are not user-friendly otherwise.

Below follows a description of the files and directories you can find in this repository.

* **p4include** contains _core.p4_ and _NDNcore.p4_.
   - The first file is authored by the P4 Consortium. It contains core P4 features that, in principle, any architecture should support, such as the lpm, exact or ternary match kinds.
   - The second was written for this project, and contains all type definitions according to the [NDN packet format specification](https://named-data.net/doc/NDN-packet-spec/current/types.html#types).
* **p4architecture** contains _v1model.p4_, by the P4 Consortium, and _EtherNDNSampleArchitecture.p4_, written for this project.
   - _v1model.p4_ is the architecture that was assumed default for any P4 device in P4-14. It provides the features the language previously assumed any device would have, such as counters and registers, as well as hashing, cloning and recirculation functions. With P4-16, a very stable core was instead preferred. Devices expose their capabilities by exposing an **architecture definition file**. 
   - _EthernetNDNSampleArchitecture.p4_ is essentially an architecture definition file that we'd expect to find for a device that supports the NDN communications protocol running over Ethernet. It extends v1model and defines important device parameters such as number of ports and maximum supported components, while providing additional primitives. For the rest of the source code, these new primitives are unimportant, as they were not actually implemented.
* **p4src**, containing all implemented NDN router logic. A README inside the directory provides further information.

Besides these, the repository also hosts:

* An NDN packet generator programmed in C, **rawpkt**;
* A python script to generate entries for the Forwarding Information Base (FIB), called **makeFIBrules2.py**, originally by Salvatore Signorello and available publicly in [his repository](https://github.com/signorello/NDN.p4), adapted for our solution.
* \[OUTDATED\] A modification of the **simple\_switch** architecture from the [Behavioral Model 2](https://github.com/p4lang/behavioral-model) (BMv2).
* **TARGET_bmv2-ss**, a directory that can be copy-and-pasted to the [p4lang tutorials repository](https://github.com/p4lang/tutorials) under _P4D2\_2017/exercises_. That repository offers a prepared environment to boot up mininet with a switch running a given P4-16 program.

## makeFIBrules2.py

This section describes the `makeFIBrules2.py` script, used to setup FIB entries.

### Hashestray
Recall that we employ hashes to construct the **hashestray**, or **hashtray** for short. An entry in the FIB is a hashtray, which is a structure divided in _n_ blocks, where each block inholds the result of the hash calculation of the NDN name component at the homologue position. A device that supports at most 4 components builds 4 block hashtrays. Such a device would build a hashtray from "a/b/c" as:

| h("a") | h("b") | h("c") |  0  |

### The script
When inserting a route onto the FIB, the hash calculations of its components must be performed and the hashtray must be built. This script, **makeFIBrules2.py** constructs the hashtray and attaches a mask based on:

* the number of components on the route and 
* the hash function output length.

Using this script assumes two files: an INPUT file of text, containing the entries that we wish to add to the FIB and the desired output interface for them separated by space; a second OUTPUT file that the script edits to **_append_** the entry/hashtray and its mask. Remember this when using the script, because the second file will never have its contents overriden, which means the output of previous uses of the script remain unaltered.

Routes are arranged by the control plane, which is out of the scope of P4. This is why, in practice, routes become fixed from the moment Mininet is launched.

Use as follows: `makeFIBrules2.py --fib in.txt --cmd out.txt`, where in.txt is the INPUT file and out.txt is the OUTPUT file.

Assuming the script is set for 4 maximum components and uses the crc-32 hash function (32 bits output), if in.txt is:

>/uk/cam 2
>
>/pt/ul/fc 3
>
>/portugal/unlisboa/fciencia/index.ht 1

Then the script appends the following lines to out.txt.

>table_add fib Set_outputport 0xc9f1279cfa35eb680000000000000000/64 => 2
>
>table_add fib Set_outputport 0x398ede2c5795b23fa6c5ee3c00000000/96 => 3
>
>table_add fib Set_outputport 0xd7af62ae5b069ba2a833f2ebd5ac5123/128 => 1


## simple\_switch

**WARNING:** The directory with the modified simple\_switch files has not been revised since July 2017, and may no longer be working. 

Is unnecessary if you don't need the Content Store. We have implemented a Content Store directly onto the switch architecture. Further info will be made available in a README file inside the folder, but, for now, and until a large change happens to those files in the BMv2 repository, the files can simply be replaced. The switch must then be recompiled using **make**.

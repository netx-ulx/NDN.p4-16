# NDN.p4-16 Experiment

This folder contains all the files necessary to run as a P4D2\_2017 exercise. P4D2\_2017 is a directory of the [p4lang tutorials repository](https://github.com/p4lang/tutorials) prepared to boot the BMv2 switch in Mininet, running a given P4-16 program.


## This directory

For commodity, this directory contains:

* A copy of the p4src files with minimal changes;
* A compiled `rawpkt` executable. Refer to the rawpkt directory in this repository for documentation;
* `makeFIBrules2.py`, to perform crc-32 calculation on FIB entries. Refer to the index of the NDN.p4-16 repository for documentation.

You will also find other files made for this experiment, such as:

* **FIB.txt**, which lists the FIB entries and the respective outgoing physical ports;
* **data** and **mega**, two dummy files for NDN _Data_ packets. Both inhold 8-byte strings: "_HaveData_" and "_AlfoMega_" respectively. Remember per our documentation in the p4src directory that these strings necessarily have 8 bytes exactly.

Finally, you will find files common to all P4D2\_2017 exercises:

* **s1-commands.txt**, with entries to add to the ingress or egress pipelines of switch s1. For commodity, we ran `makeFIBrules2.py` with the current FIB.txt, so the resulting entries are already recorded in s1-commands.txt.
* **p4app.json** is a JSON defining the topology. It is currently defined to create a switch and 4 hosts. Refer to other P4D2\_2017 exercises to find out how to create topologies with multiple switches.
* **run.sh** is a bash script that boots up Mininet with the chosen topology. In addition, we inserted a line, `sudo mn -c`, so that you don't need to run it whenever you start this setup.


## Why is a different version necessary?

Unlike its predecessor version, P4-16 is less independent of its underlying architecture. This change in language paradigm was so devices could expose more of their capabilities to the programmer. The reverse of the medal is programs will frequently need to be adapted. 

In our case, BMv2 simple\_switch has a number of limitations on its support to the P4-16 language features. Namely:

* Externs can't be called from the parser;
* Defining header\_unions yields a compiler bug (https://github.com/p4lang/p4c/tree/master/backends/bmv2);
* Using stacks of variable-length headers is not possible (https://github.com/p4lang/p4c/tree/master/backends/bmv2);
* Sub-parsers cannot carry metadata ([p4lang/p4c/#698](https://github.com/p4lang/p4c/issues/698));
* One cannot index into a header stack using a variable, e.g. by writing `hs[i]`, only compile-time known values can be used as indexes;
* Shift-left and shift-right must be no longer than 255 bits;
* Explicit transitions to the reject state are forbidden (https://github.com/p4lang/p4c/tree/master/backends/bmv2).

In light of this, the program must suffer changes. These are designated below:

* All TLVs have 1 byte of Type, 1 byte of Length and 8 bytes of Value, except TLV<sub>0</sub> and TLV<sub>N</sub>.
* The sub-parser has been removed (since all TLVs become fixed-size, we don't need it anyway);
* Hashing components has been moved to the ingress pipeline.
   - Since the only possibility of cycling is in the parser, we must duplicate code for as many components as we support.


## OS and app setup

These experiments were run on an Ubuntu 16.04 with:

* Native installation of mininet;
* Cloned copy of [BMv2](https://github.com/p4lang/behavioral-model); 
* Cloned copy of [p4c](https://github.com/p4lang/p4c), the P4 compiler.
* Cloned copy of the [tutorials repository](https://github.com/p4lang/tutorials), linked above.

Follow very rigorously the instructions in each of the abovementioned. Once you have all of these setup correctly and working, take the following steps.
 
1. Copy this folder, **v7**, into `P4D2_2017_Spring/exercises`.
1. Change the following lines on `P4D2_2017_Spring/utils/p4apprunner.py` to point to your local copies of BMv2 and p4c:
   - Line 118, from `p4c-bm2-ss` to e.g. `~/p4c/build/p4c-bm2-ss`.
   - Line 187, the string `simple_switch` to `~/behavioral-model/targets/simple_switch/simple_switch`.
1. For multicast to work, modify the BMv2 simple\_switch by accessing the _~/behavioral-model/targets/simple\_switch_ directory. Then, open up file simple\_switch.c and:
   - Comment out lines 509, 510, 520 and 521.
   - Insert the following code after line 520:
>   `Field &m_nextegress = phv->get_field("scalars.Metadata.next_egress_spec");`
>   `enqueue(m_nextegress.get_int(), std::move(packet_copy));`

Recompile the switch by opening a terminal and writing `make`.


## Running mininet

To start mininet, run the command: `./run.sh`.

## Experiments

In the mininet environment, you can run a multitude of commands. For example, we can know which nodes are available with `nodes` and find out the interfaces of switch s1 with command `py s1.intfs`.

> mininet\> nodes
>
> available nodes are: 
> 
> h1 h2 h3 h4 s1
>
> mininet\> py s1.intfs
>
> {0: \<Intf lo\>, 1: \<Intf s1-eth1\>, 2: \<Intf s1-eth2\>, 3: \<Intf s1-eth3\>, 4: \<Intf s1-eth4\>}

We tested features by making use of rawpkt to create NDN packets and then capturing them with tcpdump. Capture the traffic reaching a host X by typing `xterm hX` on the mininet console. On the xterm window that just spawned, write:

```tcpdump -i hX-eth0 ether proto 0x8624```

Let us now test the NDN features expressed in the P4 program. Do not tear down Mininet at any step. You may safely ignore MAC addresses.


### 1. FIB longest-prefix-match

* Open an xterm on h1 and start tcpdump with the abovementioned recipe.
* Make host 2 send an _Interest_ for the default name, "portugal/unlisboa/fciencia/index.ht", by writing `h2 ./rawpkt -i h2-eth0` on the Mininet console.
   - Notice h1 receives this Interest. Remember our FIB contains 3 prefixes of the default name, but the longest one, towards h1, was selected.

### 2. _Interest_ state maintenance
* Repeat the above step for host 3.
   - Notice h1 does **not** receive this Interest. This is correct behavior, because the NDN router should only emit _Interests_ once.


### 3. Spurious _Data_ elimination

* Open xterms on h2, h3 and h4 by writing `xterm h2 h3 h4`. Start tcpdump in all the opened xterms.
* Make h1 send a _Data_ by writing on the Mininet console `h1 ./rawpkt -i h1-eth0 -f mega -n "portugal/unlisboa/fciencia"`.
   - Option `-f` sets the packet type to _Data_. It also appends the content of file `mega` as a Content TLV.
   - Option `-n` sets the name. The string "AlfoMega" should be spottable in the tcpdump ASCII output, the same way you may have noticed strings of the name components.
   - Note that only h1 records emitting this packet. The switch drops it because the Interests we emitted earlier carried the default name, "portugal/unlisboa/fciencia/index.ht", and this _Data_ was unsolicited.

### 4. Multicast
* Make h1 send a _Data_ by writing on the Mininet console `h1 ./rawpkt -i h1-eth0 -f data`.
  - The lack of option `-n` means the name is the default one. It matches the name h2 and h3 requested exactly.
  - Notice h2 and h3 receive the _Data_, but h4 does not. Since h2 and h3 requested it but h4 didn't, this is correct behavior.
  
  
  
## TODO

There are certain awkward behaviors one can induce. Namely, we could make h4 send the _Data_ requested by h2 and h3, even though our FIB indicates the path towards that content is through h1. Also, h1 can send an Interest for the default name, and the NDN router will throw the packet back to him. In this case, if h1 satisfies his own request, he will also receive back the Data packet he sent.

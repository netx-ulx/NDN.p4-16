# NDN.p4-16

This repository contains the source code for "Named Data Networking using Programmable Switches", a master's dissertation by Rui Miguel and supervised by Fernando Ramos, both from the Faculty of Sciences ("FCiências") of the University of Lisbon ("ULisboa").

Besides the P4 program, this repository also hosts:

* An NDN packet generator programmed in C, which we called **rawpkt**;
* A python script to generate entries for the Forwarding Information Base (FIB), called **makeFIBrules2.py**, originally by Salvatore Signorello and available publicly in [his repository](https://github.com/signorello/NDN.p4). It has been adapted for our solution.
* A modification of the **simple\_switch** architecture from the [Behavioral Model 2](https://github.com/p4lang/behavioral-model) (BMv2).



## rawpkt

Generates NDN packets. A README inside the rawpkt folder will provide more information.

## makeFIBrules2.py

### Hashestray
Recall that we employ hashes to construct the **hashestray**, or **hashtray** for short. An entry in the FIB is a hashtray, which is a structure divided in _n_ blocks, where each block inholds the result of the hash calculation of the NDN name component at the homologue position. A device that supports 4 components at most builds 4 block hashtrays. Such a device would build a hashtray from "a/b/c" as:

| h("a") | h("b") | h("c") |  0  |

### The script
When inserting a route onto the FIB, the hash calculations of its components must be performed and the hashtray must be built. This script, **makeFIBrules2.py** constructs the hashtray and attaches a mask based on:

* the number of components on the route and 
* the hash function output length.

Using this script assumes two files: an INPUT file of text, containing the entries that we wish to add to the FIB and the desired output interface for them separated by space; a second OUTPUT file that the script edits to **_append_** the entry/hashtray and its mask. Remember this when using the script, because the second file will never have its contents overriden, which means the output of previous uses of the script remain unaltered.

Routes are arranged by the control plane, which is out of the scope of P4. This is why, in practice, routes become fixed from the moment Mininet is launched.

Use as follows: `makeFIBrules2.py --fib in.txt --cmd out.txt`, where fib.txt is the INPUT file and commands.txt is the OUTPUT file.

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

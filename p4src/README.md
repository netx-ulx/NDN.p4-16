# NDN.p4-16 source files

This folder contains all source code for the P4 program. It also borrows from the p4include and p4architecture folders.

## Items

* **defs.p4** contains all macro, typedef, struct and header definitions.
* **Parser.p4** is the main parser of the project.
* **FixedLengthParser.p4** is a backup parser for the BMv2 simple\_switch, which does not support header unions or varbit fields. It also seems to be misbehaving when reasoning about extern functions.
* **Ingress.p4** is the ingress pipeline. It is the main block of code that deals with NDN packet processing.
* **Egress.p4** is the egress pipeline. Other than applying Ethernet header changes, it also clones Data packets when they should be multicast.
* **Actions.p4** contains a set of common actions to the ingress and egress pipelines.
* **Deparser.p4** simply emits back to the network all the fields that have been processed.
* **Main.p4** is the file that should be the target of compilation. It simply includes all the files in this repository, defines unused control blocks, and instantiates the package.


## Compiling

You may compile this with either p4test or p4c-bm2-ss. Add command line argument `--p4v 16` to specify that it should compile for P4\_16. Below follow the macros available for definition at compilation time:

* **TARGET\_BMV2** -- This macro indicates that the backend is BMv2 simple\_switch, which means the `header_union` and `varbit` types are not supported.
* **CONTENT\_STORE** -- This macro indicates we compile assuming a content store extern set is present (from file _EtherNDNSampleArchitecture.p4_). This extern set has not actually been implemented, so at the moment, compiling with this macro definition only ensures the compiler fully analyzes the code at the ingress stage (_Ingress.p4_).
* **CHECK\_SIGNATURES** -- This macro indicates signatures are present and should be checked. No signature verification has actually been implemented.

When neither CONTENT\_STORE or CHECK\_SIGNATURES macros are present, the parser will stop parsing the packet after TLV<sub>N</sub>. If those TLVs are present, they are interpreted as payload. If CONTENT\_STORE is present, the Content TLV is parsed. If CHECK\_SIGNATURES is present, Content, SigInfo and SigVal TLVs are all parsed.

Assuming **p4c** and this repository are on the same directory, the command to compile can be:

> ../p4c/build/p4test --p4v 16 ./Main.p4 \[-D TARGET\_BMV2\] \[-D CONTENT\_STORE\]

## Results

Compiling with p4test should be successful in every case. The same attempt with `p4c-bm2-ss`, however, should yield a compiler bug with all but one combination of macros: TARGET\_BMV2. Without this macro, the TLV is defined as a `header_union`, and the BMv2 backend compiler hasn't yet been fully developed to support them. CONTENT\_STORE yields another bug that seemingly has to do with abstract reasoning on extern functions.

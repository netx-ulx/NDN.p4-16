# file makeFIBrules2.py
#
# This file was initially developed for NDN.p4 by Signorello et al, and is
# available on his GitHub repository: https://github.com/signorello/NDN.p4
#
# We modified it to suit our method of building FIB entries.

import os.path, time
import argparse
import datetime
from os.path import expanduser
#from crcmod.predefined import *
import sys
import zlib

table_name = "fib"
action_name = "Set_outputport"
max_components = 16
hash_function = "siphash" #Keep this in mind!

def parse_args():
    usage = """Usage: createFIBrules --fib fib.txt --cmd commands.txt [-t table_name] [-a action_name] [-c max_components] [-f has_function]
    fib.txt contains the FIB entries listed into separate lines
    commands.txt is the ouput file the produced command rules will be appended to
    """

    parser = argparse.ArgumentParser(usage)

    parser.add_argument('--fib', help='file containing the FIB records',
                        type=str, action="store", required=True)
    parser.add_argument('--cmd', help='file FIB rules will be appended to',
                        type=str, action="store", required=True)
    parser.add_argument('-t', help='Name of the table to be used into the output file records',
                            type=str, action="store", dest="table_name")
    parser.add_argument('-a', help='Name of the action to be used into the output file records',
                            type=str, action="store", dest="action_name")
    parser.add_argument('-c', help='max number of name components supported by the device to be programmed',
                            type=int, action="store", dest="max_components")
    parser.add_argument('-f', help='function used to compute an hash of the full name, default is crc16',
                            type=str, action="store", dest="hash_function")

    return parser.parse_args()

def convert_rules(fib_file, cmd_file):
    if not os.path.isfile(fib_file):
            print "File %s does not exist" % fib_file
	    sys.exit(-1)
    else:
      print "Reading FIB entries from %s" % fib_file

    print "Appending commands to %s" % cmd_file

    out_file = open(cmd_file, 'a')

    lines = [line.rstrip('\n') for line in open(fib_file)]

    for entry in lines:
      process_entry(entry, out_file)

    out_file.close()


# Entry priority is assigned as follows:
# priority = max_components - num_components + 1 
# lower values give higher priority
def process_entry(entry, out_file):
    print 'Entry: \" %s \" maps into:' % entry
    rule = entry.split(' ')
    name = rule[0]
    iface = int(rule[1])

    # Notice that names are specified as "/comp1/comp2/..."
    # Means the first component is empty. That's why it's being popped
    name_components = name.split('/')
    name_components.reverse()
    name_components.pop()
    name_components.reverse()

    
    hashed_components = '0x'
    n = len(name_components) * 32
    i = len(name_components)

    for component in name_components:
      hash_name = format(zlib.crc32(component) % (1<<32), 'x').zfill(8)
      hashed_components = '%s%s' % (hashed_components,hash_name)
    while i < max_components:
      hashed_components = '%s%s' % (hashed_components,'00000000')
      i += 1


    # table_add fib_table set_egr  => 1 1
    rule = 'table_add %s %s %s%s%d => %d\n' % (table_name, action_name, hashed_components, '/', n, iface)
    out_file.write(rule)
    print '\t' + rule


def main():
    global table_name, action_name, max_components, hash_function 

    args = parse_args()
    if args.table_name is not None:
      table_name = args.table_name
    if args.action_name is not None:
      action_name = args.action_name
    if args.max_components is not None:
      max_components = args.max_components

    convert_rules(args.fib, args.cmd)

if __name__ == '__main__':
    main()

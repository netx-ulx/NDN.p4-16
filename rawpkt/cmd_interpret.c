#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "defs.h"

//GLOBAL VARIABLES
unsigned int PARAM_pktcount;
unsigned int PARAM_sendpktinterval = 0;
unsigned char PARAM_cmpvari = 0;

char * ifacename;
char * const DEFAULT_IFACE = "eth0";

char custom_deth = 0;
unsigned short scan_mode = 1;


char * name;
char DEFAULT_NAME[41] = "portugal/unlisboa/fciencia/index.ht";

char * filename;



//================


void interpret(int argc, char** args, unsigned char* sendbuf) {

  int count = 1; //first argument in C is always the program name
  ifacename = NULL;
  name = NULL;
  filename = NULL;

  for(; count < argc ; count++)
  {
/* =======================================================================
 * --- OPTION:  -i
 * =======================================================================
 * Sets the outgoing interface of this packet generator.
 */
    if (strncmp(args[count], "-i", 2) == 0)
    {
      ifacename = args[++count];
    }
     
/* =======================================================================
 * --- OPTION:  -c <num>
 * =======================================================================
 * Makes the packet generator send <num> packets.
 */
    else if (strncmp(args[count], "-c", 2) == 0)
    {
      PARAM_pktcount = strtoul(args[++count], NULL, 10);//10 is decimal base
    }

/* =======================================================================
 * --- OPTION:  -n
 * =======================================================================
 * Sets the name inheld by the generated Interest(s). Names are divided
 * into components.
 */
    else if (strncmp(args[count], "-n", 2) == 0)
    {
      if (strlen(args[++count]) <= 80)
        name = args[count];
      else {
        printf("WARNING: Too large name. Using default: %s.", DEFAULT_NAME);
      }
    }

/* =======================================================================
 * --- OPTION:  -f <file>
 * =======================================================================
 * Sets the packet type to Data and appends the following file contents.
 * WARNING: This file MUST inhold 8 characters.
 */
    else if (strncmp(args[count], "-f", 2) == 0)
    {
      filename = args[++count];
    }

/* =======================================================================
 * --- OPTION:  -t, --time <interval>
 * =======================================================================
 * Sets the interval between two packet transmissions, in miliseconds.
 */
    else if (strncmp(args[count], "-t", 2) == 0
          || strncmp(args[count], "--time", 6) == 0)
    {
      PARAM_sendpktinterval = strtol(args[++count], NULL, 10);
    }
     
    
/* =======================================================================
 * --- OPTION:  -r <rounds>
 * =======================================================================
 * Number of bursts to send (by the generator) or receive (by the listener).
 * WARNING: Remember the router only replies once because the PIT stores the
 * request. If you want to use this option, you'll have to make sure the router
 * consults the FIB every time, otherwise rawpkt becomes stuck.
 */
    else if (strncmp(args[count], "-r", 2) == 0)
    {
      scan_mode = strtol(args[++count], NULL, 10);
    }
    
/* =======================================================================
 * --- OPTION:  -vc / --vary-components <n>
 * =======================================================================
 * Each round, the number of components varies by n. Maximum variation of 255
 * (unsigned char). A round is determined by -r, not -c.
 */
    else if (strncmp(args[count], "-vc", 3) == 0 || !strncmp(args[count], 
                                                    "--vary-components", 17))
    {
      PARAM_cmpvari = (unsigned char) strtol(args[++count], NULL, 10);
    }
    
/* =======================================================================
 * --- OPTION:  -d, -deth
 * =======================================================================
 * Sets the destination MAC on the link-layer header of this packet.
 */
    else if (!strncmp(args[count], "-deth", 5) || !strncmp(args[count], "-d", 2))
    {
      custom_deth = 1;

      const size_t MACaddrsize = strlen(args[++count]);

      if (MACaddrsize > strlen("00:00:00:00:00:00") ) {
        fprintf(stderr, "ERROR: -d(eth) argument too large.\n");
        exit(7);
      }

      unsigned char i = 0; //iteration variable
      uint64_t final_result = 0; //6 bytes of it are copied to the buffer
      uint8_t next_msb; //next most significant byte (4 upper bits)
      uint8_t next_lsb; //next least significant byte (4 lower bits)

      while (i < MACaddrsize) {
        next_msb = chrtohex( args[count][i] );
        i++; //chrtohex() is a macro. Do NOT write i++ inside the call!
        next_lsb = args[count][i];

        if (next_lsb != ':' && next_lsb != '\0') {
          next_msb <<= 4;
          next_msb |= (chrtohex(next_lsb) & 0xf);
          i++;
        }

        final_result |= next_msb;
        final_result <<= 8;

        i++;
      }

      sendbuf[0] = final_result >> 48;
      sendbuf[1] = final_result >> 40;
      sendbuf[2] = final_result >> 32;
      sendbuf[3] = final_result >> 24;
      sendbuf[4] = final_result >> 16;
      sendbuf[5] = final_result >> 8;

    }//end of the ifs that check program arguments

  }//end of the outer for cycle where program arguments are checked


  if (ifacename == NULL)
    ifacename = DEFAULT_IFACE;
  if (name == NULL)
    name = DEFAULT_NAME;

}

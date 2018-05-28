#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h> //gettimeofday()
#include <arpa/inet.h>
#include <net/if.h>
#include <netpacket/packet.h>
#include <netinet/ip.h>
#include <netinet/udp.h>
#include <netinet/ether.h>
#include <unistd.h>
#include <errno.h>

#include "defs.h"


extern unsigned int PARAM_pktcount;
extern unsigned int PARAM_sendpktinterval;
extern unsigned char PARAM_cmpvari;
extern char * ifacename;
extern char custom_deth;//bool
extern unsigned char * name;
extern char * filename;
extern unsigned short scan_mode;

unsigned char sendbuf[256];
unsigned char recvbuf[512];




//=========================================================================
int main(int argc, char** args) {

  int sockfd;
  struct ifreq ifr;
  unsigned int ptr = sizeof(struct ether_header) + 1;


  //Initialize globals
  ifacename = NULL;
  name = NULL;
  PARAM_pktcount = 1;
  scan_mode = 0;


  // 0 -- Interpret program arguments
  interpret(argc, args, sendbuf);


  // 1 -- Open RAW socket to send on
  // ------ SOCK_RAW leaves the Ethernet header to be written by the programmer
  // ------ SOCK_DGRAM makes the operating system fill it in automatically
  if ((sockfd = socket(AF_PACKET, SOCK_RAW, htons(0x8624))) == -1) {
    perror("socket()");
    //exit(3);
  }

  // 2 -- Requesting to know an interface's MAC address, given its name
  ifr.ifr_addr.sa_family = AF_INET;
  strncpy(ifr.ifr_name, ifacename, IFNAMSIZ-1);
  
  //SIOCGIFHWADDR, SIOCSIFHWADDR
  //   Get or set the hardware address of a device using ifr_hwaddr. (from Linux man)
  if (ioctl(sockfd, SIOCGIFHWADDR, &ifr) < 0)
    perror("Error was SIOCGIHWADDR");

  const unsigned char * mac = (unsigned char *)ifr.ifr_hwaddr.sa_data;

  // 3 -- Filling in packet
  struct ether_header * eh = (struct ether_header *) sendbuf;


  // Ethernet header
   //NOTICE: We're pointing to the buffer! The following statements set data!
  if (!custom_deth) {
   eh->ether_dhost[0] = 0;
   eh->ether_dhost[1] = 1;
   eh->ether_dhost[2] = 0;
   eh->ether_dhost[3] = 0;
   eh->ether_dhost[4] = 0;
   eh->ether_dhost[5] = 1 - mac[5];
  }

  eh->ether_shost[0] = mac[0];
  eh->ether_shost[1] = mac[1];
  eh->ether_shost[2] = mac[2];
  eh->ether_shost[3] = mac[3];
  eh->ether_shost[4] = mac[4];
  eh->ether_shost[5] = mac[5];

  eh->ether_type = htons(0x8624);


  const size_t pktsize = filename != NULL ? 
fill_data(sendbuf, name, &ptr, filename) : fill_interest(sendbuf, name, &ptr);
  // fill_interest() returns pktsize on top of filling the Interest's fields

  unsigned int i;
/*
  for(i=0 ; i < sizeof(struct ether_header) + pktsize + TYPE + LENCODE ; i++)
    if (i < sizeof(struct ether_header) )
	printf("Character no %d: %02x\n", i, sendbuf[i]);
    else
	printf("Character no %d: %c\n", i, sendbuf[i]);
*/
   
  //SIOCGIFINDEX - Retrieve the index of the interface into ifr_ifindex.
  if (ioctl(sockfd, SIOCGIFINDEX, &ifr) < 0)
    perror("ERROR: SIOCGIFINDEX or ifr_ifindex.");

 /* The Linux manual states the send() and sendto() functions are equivalent
  * for a NULL socket_address, but RAW requires a socket_address, as it will
  * yield errno=6=ENXIO, "No such device or address", otherwise.
  * Though the manual does state that send() is intended for connected sockets, 
  * at the RAW level there's no concept of connection, so using send() is a
  * semantic error.
  */
  struct sockaddr_ll socket_address;

  //Prepare the socket_address struct
  socket_address.sll_family = PF_PACKET;
  //socket_address.sll_protocol = 0xaaaa;
  socket_address.sll_ifindex = ifr.ifr_ifindex;
  socket_address.sll_hatype = ARPHRD_ETHER;
  socket_address.sll_pkttype = PACKET_OTHERHOST;
  socket_address.sll_halen = ETH_ALEN;


  // --- 1. Prepare stack data
  const unsigned short initial_scan_mode = scan_mode + 1;
  
  unsigned short success = 0;
 
  while (scan_mode > 0) {
    
    i = 0;
    
    printf("> INFO: Initiating round %hu...", initial_scan_mode - scan_mode);
    fflush(stdout); //printf() needs '\n' to flush contents,
    // but we want it to display immediately, hence fflush().

    
    // --- 2. Send packet burst
    for (i=0; i < PARAM_pktcount; i++) {
      sendto(sockfd, sendbuf, pktsize+TYPE+LENCODE+sizeof(struct ether_header),
        0, (struct sockaddr*)&socket_address, sizeof(socket_address));
      usleep(PARAM_sendpktinterval);
    }
    
    printf(" Completed!" + initial_scan_mode > 1 ? 
                          " Expecting listener feedback." : "");
    fflush(stdout);
    
    // --- 3. Expect a response from listener with lost packets.
    // Then, grab the nonce; it has number of packets received.
    ssize_t msgsize;
    
    if (initial_scan_mode > 1) {
      usleep(1750000); //try not to catch any sent packet (is this possible?)

      recvbuf[12] = 0; //Otherwise the cycle ends immediately
      while (recvbuf[12] != 0x86 || recvbuf[13] != 0x24) {
        msgsize = recvfrom(sockfd, recvbuf, 512, 0, NULL, 0);
        //Will be stuck here until listener's socket times out (~3 secs)
      }


      const int * const nonce = (const int *) ((&recvbuf[msgsize]) - 4);
      const unsigned int lpktsrcvd = ntohl(*nonce);

      printf(" Listener received %u packets.", lpktsrcvd);


      // --- 4. Change interval between packet emissions according to the
      // feedback provided by the listener. Print info.
      if (lpktsrcvd == PARAM_pktcount) {
        ++success;

        if (success >= 4 && PARAM_sendpktinterval > 0 ) {
          PARAM_sendpktinterval -= 5 + 5 * (PARAM_sendpktinterval / 100);
          printf(" Since I succeeded 4 times, I'm diminishing inter-packet"
                 "interval to %u.\n\n", PARAM_sendpktinterval);
          success = 0;
        } else {
          printf("\n\n");
        }

      } else { //Not all packets were received
        success = 0;
        PARAM_sendpktinterval += 5;
        printf(" Packets were lost. Increasing inter-packet interval to "
               "%u.\n\n", PARAM_sendpktinterval);
      }
    }
    // --- 5. Begin new round
    scan_mode--;
  }
  
  close(sockfd);
   
  return 0;
}

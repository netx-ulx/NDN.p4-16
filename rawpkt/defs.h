#ifndef _RAWPKTDEFS_
#define _RAWPKTDEFS_

#include <sys/ioctl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>


#define ENCODING_2BYTE 253
#define ENCODING_4BYTE 254
#define ENCODING_8BYTE 255

#define TYPE 1
#define LENCODE 1
#define NONCE_TLV_SIZE ( TYPE + LENCODE + 4 )

#define LINEAR_ASCENT_PACKETN 100

#define chrtohex(c) (((c) <= '9')   ?   ((c) - '0')  :  ((((c)-1) & 0xF) + 0xA))


unsigned long long fill_data(unsigned char * buffer,
	unsigned char * name,
	unsigned int * ptr,
	char * const contentfile);

unsigned long long fill_interest(unsigned char * buffer, unsigned char * name, unsigned int * ptr);

void fill_component(unsigned char * buffer, unsigned char * component, unsigned int * ptr);

void interpret(int argc, char** args, unsigned char * sendbuf);


void readfile(unsigned char * const buffer, char * const filename, unsigned int * ptr);

unsigned long long getfilesize(char * const filename);

#endif //_RAWPKTDEFS_

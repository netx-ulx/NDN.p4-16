#include "defs.h"

const unsigned char NAME_COMPONENT_TOKEN = '/';



/**
 * We use this function instead of comparing to the constant
 * NAME_COMPONENT_TOKEN so that, at any time, we can easily define more tokens
 * and have the program work correctly without having to go back and update
 * every function.
 */
static inline char is_component_separator_token(unsigned char test_token) {
  return test_token == NAME_COMPONENT_TOKEN;
}


/**
 * Calculates the name size. It does this by analyzing the name and
 * invoking is_component_separator_token() to discern between components.
 * Each component adds 2 bytes to the total (type and length) or more
 * depending on the necessity of a length extension.
 *
 * @requires 'name' has a null terminating byte
 *        && the first character is not a component delimiter token.
 * @return The sum of all component TLVs. Does not count with type and len
 *        from TLVN.
 */
static unsigned int calculate_name_size(const unsigned char * name)
{
  unsigned int i = 0;
  unsigned int total = TYPE + LENCODE; //This TYPE and LENCODE are from TLVName
  unsigned int lasttok = 0;

  for(i=0; name[i]!='\0'; total++, lasttok++, i++) {

    if ( is_component_separator_token(name[i]) ) {
      ++total; //+= 2;
	//We're already incrementing at the end of the cycle and we mustn't count '/'.

      if (lasttok > (ENCODING_2BYTE-1) && lasttok <= 0xffFF)
        total += 2;
      else if (lasttok > 0xffFF && lasttok <= 0x7fFFffFF)
        total += 4;

      lasttok = 0;

      //Check if we're not over the maximum allowed size
      if (total > 0x7fFFffFF) {
        fprintf( stderr, "ERROR: Total NDN packet size exceeds 0x7fFFffFF.");
        exit(2);
      }

    }
  }

  if (lasttok > (ENCODING_2BYTE-1) && lasttok <= 0xffFF)
    total += 2;
  else if (lasttok > 0xffFF && lasttok <= 0x7fFFffFF)
    total += 4;

  return total + TYPE + LENCODE; //from the last component

  //Does not count with the TYPE and LENCODE from TLV0 or Name
}

//=========================================================================
/**
 * Fills the length depending on 'size' and advances 'ptr' by the
 * corresponding number of bytes by performing the operation (*ptr)++.
 */
void fill_TLV_length(unsigned char * buffer, unsigned long long size, unsigned int * ptr) {

  if (size > 0x7fFFffFF) {
    fprintf(stderr, "ERROR: Too big TLV!");
    exit(-1);
  }

  if (size <= ENCODING_2BYTE) {
    buffer[(*ptr)++] = size;
  } else {

    const unsigned char lencode = size <= 0xffFF ? ENCODING_2BYTE : ENCODING_4BYTE;
    const unsigned char number_of_length_extension_bytes = 1 << (lencode - (ENCODING_2BYTE-1));
    //above expression yields 2, 4 or 8 depending on lencode.
    //(and assuming ENCODING_2BYTE = 253)
    char i;//Don't use unsigned char, otherwise the cycle guard is a tautology

    buffer[*ptr] = lencode;

    for( i = number_of_length_extension_bytes ; i > 0 ; i--) {
      buffer[*ptr + i] = size;
      size >>= 8;
    }

    *ptr += number_of_length_extension_bytes + 1;
  }
}


//=========================================================================
/**
 * Fills in a component for the NDN packet. It fills in a Type (0x08), the
 * lencode, the extended length, and then copies the content
 * of 'component' into 'buffer'.
 *
 * Uses strnlen() to uncover parameter 'component' length.
 */
void fill_component(unsigned char * buffer, unsigned char * component, unsigned int * ptr) {
  
  const size_t component_size = strlen((char *) component);

  //printf("INFO: Filling in next component: %s\n", component);

  // 1 -- Fill in type and lencode
  buffer[(*ptr)++] = 0x08; //NDNTYPE_Component

  fill_TLV_length(buffer, component_size, ptr);

  //2 -- Fill in the component content
  unsigned int i;
  for(i=0; i < component_size; i++)
    buffer[(*ptr)++] = component[i];

} 



//=========================================================================
/**
 * Fills an Interest packet properly formatted into 'buffer' with name and a
 * randomly generated nonce.
 *
 * Uses strnlen() to uncover parameter 'name' length.
 *
 * WARNING:
 * This function will insert null characters into 'name' at every place it
 * finds an NAME_COMPONENT_TOKEN (expected to be '/').
 */
unsigned long long fill_interest(
	unsigned char * buffer, unsigned char * name, unsigned int * ptr)
{

  const size_t name_length = strlen((char *) name);

  buffer[14] = 0x05; //NDNTYPE_INTEREST (TLV0)

  const unsigned long long packet_length =
	calculate_name_size(name) + NONCE_TLV_SIZE;

  fill_TLV_length(buffer, packet_length, ptr);

  buffer[(*ptr)++] = 0x07; //NDNTYPE_NAME (TLVn)
  fill_TLV_length(buffer, packet_length - TYPE - LENCODE - NONCE_TLV_SIZE, ptr);

  unsigned int i;
  unsigned char * next_component = name;

  for(i=0 ; i <= name_length ; i++) {
    if ( is_component_separator_token(name[i]) ) {
      name[i] = '\0'; //string terminating character
      fill_component(buffer, next_component, ptr);
      next_component = name + i + 1;//next component starts here
    }
  }

  fill_component(buffer, next_component, ptr); //last component of the name.
  //the cycle doesn't fill it because the last character is not '/', it is '\0'

  buffer[(*ptr)++] = 0x0a;
  buffer[(*ptr)++] = 4;
  
  srand(time(NULL));   // should only be called once
  const int r = abs( rand() ); // returns a pseudo-random integer between 0 and RAND_MAX

  printf("I generated the following random: %d\n", r);

  buffer[(*ptr)++] = (r >> 24);
  buffer[(*ptr)++] = (r >> 16) & 0xFF;
  buffer[(*ptr)++] = (r >> 8) & 0xFF;
  buffer[(*ptr)++] = r & 0xFF;

  return packet_length;
}



//=========================================================================
/**
 * Fills a Data packet properly formatted into 'buffer' with name and a
 * content of choice.
 *
 * Uses strnlen() to uncover parameter 'name' length.
 *
 * WARNING:
 * This function will insert null characters into 'name' at every place it
 * finds an NAME_COMPONENT_TOKEN (expected to be '/').
 */
 
unsigned long long fill_data(unsigned char * buffer,
	unsigned char * name,
	unsigned int * ptr,
	char * const contentfile) {

 buffer[14] = 0x06; //NDNTYPE_DATA

 const size_t name_length = strlen((char *) name);
 const unsigned long long contentlen = getfilesize(contentfile);
 const unsigned long long packet_length = calculate_name_size(name) + TYPE + LENCODE + contentlen;

 fill_TLV_length(buffer, packet_length, ptr);

 buffer[(*ptr)++] = 0x07; //NDNTYPE_NAME
 fill_TLV_length(buffer, packet_length - 2*TYPE - 2*LENCODE - contentlen, ptr);


 unsigned int i;
 unsigned char * next_component = name;

 for(i=0 ; i <= name_length ; i++) {
    if ( is_component_separator_token(name[i]) ) {
      name[i] = '\0'; //string terminating character
      fill_component(buffer, next_component, ptr);
      next_component = name + i + 1;//next component starts here
    }
  }

 fill_component(buffer, next_component, ptr); //last component of the name.


 buffer[(*ptr)++] = 0x15; //NDNTYPE_CONTENT

 fill_TLV_length(buffer, contentlen, ptr);

 readfile(buffer, contentfile, ptr);

 return packet_length;
}

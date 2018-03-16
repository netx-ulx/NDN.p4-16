#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include "defs.h"

unsigned long long getfilesize(char * const filename) {

  struct stat s;
  FILE * file;

  if ( (file = fopen(filename, "r")) < 0 ) {
    perror("ERROR: fopen()");
    exit(4);
  }

  if ( fstat(fileno(file), &s) < 0 ) {
    perror("ERROR: stat()");
    exit(5);
  }

  return s.st_size - 1; //There is an extra character at the end of the file
}

void readfile(unsigned char * const buffer, char * const filename, unsigned int * ptr) {

  FILE * file;
  struct stat s;

  //1 -- Try to open file for reading
  if ( (file = fopen(filename, "r")) < 0 ) {
    perror("ERROR: fopen()");
    exit(4);
  }
 

  //2 -- fstat() is used to retrieve information about a file intro struct
  //stat. It contains useful information such as file size and file system
  //block size. By extracting the block size and reading one at a time, we
  //perform more efficient I/O.
  //fileno(file) transforms FILE* to int fd (file descriptor).
  if ( fstat(fileno(file), &s) < 0 ) {
    perror("ERROR: stat()");
    exit(5);
  }

  const blksize_t blocksize = s.st_blksize;
  

  //3 -- Use malloc() to allocate the necessary space
  void * const space = malloc(blocksize);
  
  if (space == NULL) {
    perror("ERROR: malloc(). Couldn't allocate memory in heap");
    exit(6);
  }


  //4 -- Now, read the file
  ssize_t bytes_read = 0;

  while ( (bytes_read = read(fileno(file), space, blocksize)) > 0 )
  {
    memcpy( (void *)(buffer+(*ptr)), (const void *)space, bytes_read);
    *ptr += bytes_read;
  }

  //5 -- Free the temporary memory we allocated earlier
  free(space);

}

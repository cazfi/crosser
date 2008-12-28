
/* These functions are required for configure linking tests */

#include <stdlib.h>

void *malloc(size_t size)
{
  return NULL;
}

void free(void *ptr)
{}

void abort()
{}

void dl_iterate_phdr()
{}

int puts(const char *s)
{
  return 0;
}

void *memcpy(void *dest, const void *src, size_t n)
{
  return NULL;
}

void *memset(void *s, int c, size_t n)
{
  return NULL;
}

size_t strlen(const char *s)
{
  return 0;
}

int raise(int sig)
{
  return 0;
}

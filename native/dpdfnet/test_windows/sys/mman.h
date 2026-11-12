// What Ceva's contract tests ask of Linux for their guard pages, on Windows:
// mmap for pages nothing may touch, mprotect to open some of them, and the
// page size. Only what those tests use, and only for test.sh.
#ifndef RIFT_DPDFNET_TEST_MMAN_H_
#define RIFT_DPDFNET_TEST_MMAN_H_

#include <stddef.h>

// Declared here rather than through windows.h, whose macros the tests' own
// names run into.
__declspec(dllimport) void *__stdcall VirtualAlloc(void *, size_t, unsigned long,
                                                   unsigned long);
__declspec(dllimport) int __stdcall VirtualProtect(void *, size_t, unsigned long,
                                                   unsigned long *);
__declspec(dllimport) int __stdcall VirtualFree(void *, size_t, unsigned long);

#define PROT_NONE 0
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_PRIVATE 0
#define MAP_ANONYMOUS 0
#define MAP_FAILED ((void *)-1)
#define _SC_PAGESIZE 0

static inline unsigned long rift_page_access(int prot) {
  // PAGE_READWRITE, PAGE_READONLY, PAGE_NOACCESS.
  return prot & PROT_WRITE ? 0x04 : prot & PROT_READ ? 0x02 : 0x01;
}

static inline void *mmap(void *at, size_t bytes, int prot, int flags, int fd,
                         long long offset) {
  (void)flags, (void)fd, (void)offset;
  // MEM_RESERVE | MEM_COMMIT.
  void *pages = VirtualAlloc(at, bytes, 0x3000, rift_page_access(prot));
  return pages ? pages : MAP_FAILED;
}

static inline int mprotect(void *at, size_t bytes, int prot) {
  unsigned long before;
  return VirtualProtect(at, bytes, rift_page_access(prot), &before) ? 0 : -1;
}

static inline int munmap(void *at, size_t bytes) {
  (void)bytes;
  // MEM_RELEASE, which takes the whole mapping.
  return VirtualFree(at, 0, 0x8000) ? 0 : -1;
}

static inline long sysconf(int name) {
  (void)name;
  return 4096;
}

#endif  // RIFT_DPDFNET_TEST_MMAN_H_

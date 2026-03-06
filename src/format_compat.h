#ifndef FORMAT_COMPAT_H
#define FORMAT_COMPAT_H

#include <limits.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>

#if defined(__GNUC__) || defined(__clang__)
#define UT_PRINTF_LIKE(fmt_idx_, vararg_idx_) __attribute__((format(printf, fmt_idx_, vararg_idx_)))
#else
#define UT_PRINTF_LIKE(fmt_idx_, vararg_idx_)
#endif

static inline int UT_PRINTF_LIKE(3,4)
UtSprintfImpl(char *dst, size_t dstSz, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  int rc = vsnprintf(dst,
		     dstSz == (size_t)-1 ? (size_t)INT_MAX : dstSz,
		     fmt, ap);
  va_end(ap);
  return rc;
}

#if defined(__GNUC__) || defined(__clang__)
#define UtSprintf(dst_, fmt_, ...) \
  UtSprintfImpl((dst_), __builtin_object_size((dst_), 1), (fmt_), ##__VA_ARGS__)
#else
#define UtSprintf(dst_, fmt_, ...) \
  UtSprintfImpl((dst_), (size_t)-1, (fmt_), ##__VA_ARGS__)
#endif

#endif

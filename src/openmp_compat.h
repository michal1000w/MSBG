/******************************************************************************
 *
 * OpenMP compatibility wrapper.
 *
 * If OpenMP is enabled in the compiler (_OPENMP), this forwards to the
 * platform omp runtime header. Otherwise, lightweight serial stubs are
 * provided so code can compile and run without OpenMP.
 *
 ******************************************************************************/
#ifndef MSBG_OPENMP_COMPAT_H
#define MSBG_OPENMP_COMPAT_H

#ifdef __cplusplus
#include <thread>
#endif

#if defined(_OPENMP)
#include <omp.h>
#define MSBG_OPENMP_BACKEND_NAME "OpenMP runtime"
#else

#define MSBG_OPENMP_BACKEND_NAME "OpenMP stubs"

#ifdef __cplusplus
extern "C" {
#endif

static inline int msbg_omp_hw_threads(void) {
#ifdef __cplusplus
  const unsigned int n = std::thread::hardware_concurrency();
  return n == 0 ? 1 : (int)n;
#else
  return 1;
#endif
}

static inline int omp_get_thread_num(void) {
  return 0;
}

static inline int omp_get_num_threads(void) {
  return 1;
}

static inline int omp_get_max_threads(void) {
  return msbg_omp_hw_threads();
}

static inline int omp_get_num_procs(void) {
  return msbg_omp_hw_threads();
}

static inline void omp_set_num_threads(int n_threads) {
  (void)n_threads;
}

static inline int omp_in_parallel(void) {
  return 0;
}

#ifdef __cplusplus
}
#endif

#endif  // _OPENMP

static inline const char *msbg_openmp_backend_name(void) {
  return MSBG_OPENMP_BACKEND_NAME;
}

#endif  // MSBG_OPENMP_COMPAT_H

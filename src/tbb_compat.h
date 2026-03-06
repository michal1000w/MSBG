/******************************************************************************
 *
 * oneTBB compatibility wrapper.
 *
 * Uses oneTBB when available unless MSBG_TBB_FORCE_FALLBACK is defined.
 * Provides a small std::thread-based fallback for the subset of APIs used by
 * MSBG when oneTBB is not available.
 *
 ******************************************************************************/
#ifndef MSBG_TBB_COMPAT_H
#define MSBG_TBB_COMPAT_H

#if !defined(MSBG_TBB_FORCE_FALLBACK)
  #if defined(__has_include)
    #if __has_include(<tbb/tbb.h>)
      #include <tbb/tbb.h>
      #define MSBG_TBB_AVAILABLE 1
    #endif
  #endif
#endif

#ifdef MSBG_TBB_AVAILABLE

#define MSBG_TBB_BACKEND_NAME "oneTBB"
inline const char *msbg_tbb_backend_name(void) {
  return MSBG_TBB_BACKEND_NAME;
}

#else

#define MSBG_TBB_BACKEND_NAME "std::thread fallback"

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <thread>
#include <vector>

namespace tbb {

namespace msbg_detail {

inline std::size_t hw_concurrency() {
  const unsigned n = std::thread::hardware_concurrency();
  return n == 0 ? 1u : static_cast<std::size_t>(n);
}

inline std::atomic<std::size_t> &max_parallelism_storage() {
  static std::atomic<std::size_t> value(hw_concurrency());
  return value;
}

inline std::size_t max_parallelism() {
  std::size_t value = max_parallelism_storage().load(std::memory_order_relaxed);
  return value == 0 ? 1 : value;
}

inline thread_local int current_thread_index = 0;

inline void set_thread_index(int tid) {
  current_thread_index = tid;
}

}  // namespace msbg_detail

template <typename Index>
class blocked_range {
public:
  blocked_range(Index begin, Index end) : _begin(begin), _end(end) {}

  Index begin() const {
    return _begin;
  }

  Index end() const {
    return _end;
  }

private:
  Index _begin;
  Index _end;
};

template <typename Range, typename Func>
inline void parallel_for(const Range &range, const Func &func) {
  using Index = decltype(range.begin());
  const Index begin = range.begin();
  const Index end = range.end();

  if (!(begin < end)) {
    return;
  }

  const std::size_t total = static_cast<std::size_t>(end - begin);
  std::size_t workers = msbg_detail::max_parallelism();
  workers = std::min<std::size_t>(workers, total);
  if (workers <= 1) {
    msbg_detail::set_thread_index(0);
    func(range);
    return;
  }

  const std::size_t chunk = (total + workers - 1) / workers;
  std::vector<std::thread> threads;
  threads.reserve(workers - 1);

  for (std::size_t worker = 1; worker < workers; ++worker) {
    const std::size_t lo = worker * chunk;
    if (lo >= total) {
      break;
    }
    const std::size_t hi = std::min(lo + chunk, total);
    threads.emplace_back([&func, begin, lo, hi, worker]() {
      msbg_detail::set_thread_index(static_cast<int>(worker));
      func(blocked_range<Index>(begin + static_cast<Index>(lo),
                                begin + static_cast<Index>(hi)));
    });
  }

  const std::size_t main_hi = std::min(chunk, total);
  msbg_detail::set_thread_index(0);
  func(blocked_range<Index>(begin, begin + static_cast<Index>(main_hi)));

  for (std::thread &thread : threads) {
    thread.join();
  }
  msbg_detail::set_thread_index(0);
}

template <typename Iter, typename Comp>
inline void parallel_sort(Iter begin, Iter end, Comp comp) {
  std::sort(begin, end, comp);
}

class this_task_arena {
public:
  static int current_thread_index() {
    return msbg_detail::current_thread_index;
  }

  static int max_concurrency() {
    return static_cast<int>(msbg_detail::max_parallelism());
  }
};

class global_control {
public:
  enum parameter {
    max_allowed_parallelism
  };

  global_control(parameter, std::size_t value) {
    _old = msbg_detail::max_parallelism();
    msbg_detail::max_parallelism_storage().store(value == 0 ? 1 : value,
                                                 std::memory_order_relaxed);
  }

  ~global_control() {
    msbg_detail::max_parallelism_storage().store(_old, std::memory_order_relaxed);
  }

private:
  std::size_t _old = 1;
};

}  // namespace tbb

inline const char *msbg_tbb_backend_name(void) {
  return MSBG_TBB_BACKEND_NAME;
}

#endif  // MSBG_TBB_AVAILABLE

#endif  // MSBG_TBB_COMPAT_H

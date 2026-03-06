/******************************************************************************
 *
 * oneTBB compatibility wrapper.
 *
 * Uses oneTBB when available unless MSBG_TBB_FORCE_FALLBACK is defined.
 * Provides a small sequential fallback for the subset of APIs used by MSBG.
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

#ifndef MSBG_TBB_AVAILABLE

#include <algorithm>
#include <cstddef>
#include <thread>

namespace tbb {

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
  func(range);
}

template <typename Iter, typename Comp>
inline void parallel_sort(Iter begin, Iter end, Comp comp) {
  std::sort(begin, end, comp);
}

class this_task_arena {
public:
  static int current_thread_index() {
    return 0;
  }

  static int max_concurrency() {
    const unsigned n = std::thread::hardware_concurrency();
    return n == 0 ? 1 : static_cast<int>(n);
  }
};

class global_control {
public:
  enum parameter {
    max_allowed_parallelism
  };

  global_control(parameter, std::size_t) {}
};

}  // namespace tbb

#endif  // !MSBG_TBB_AVAILABLE

#endif  // MSBG_TBB_COMPAT_H

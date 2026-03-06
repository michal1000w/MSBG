#ifndef MSBG_HEADER_ONLY_HPP
#define MSBG_HEADER_ONLY_HPP

#ifndef MSBG_HEADER_ONLY
#define MSBG_HEADER_ONLY 1
#endif

// Legacy C implementation units use 'register' heavily.
// Clang in C++17 treats it as an error, so erase it in this amalgamated TU.
#ifdef __cplusplus
#define register
#endif

#include "gwx_impl.hpp"
#include "mtool_impl.hpp"
#include "util_impl.hpp"
#include "util2_impl.hpp"
#include "plot_impl.hpp"
#include "rand_impl.hpp"
#include "bitmap_impl.hpp"
#include "panel_impl.hpp"
#include "readpng_impl.hpp"
#include "sbg_impl.hpp"
#include "thread_impl.hpp"
#include "fastmath_impl.hpp"
#include "blockpool_impl.hpp"
#include "grid_impl.hpp"
#include "bitmap2_impl.hpp"
#include "pnoise_impl.hpp"
#include "pnoise2_impl.hpp"
#include "pnoise3_impl.hpp"
#include "msbg_impl.hpp"
#include "msbg2_impl.hpp"
#include "msbg3_impl.hpp"
#include "msbg4_impl.hpp"
#include "halo_impl.hpp"
#include "visualizeSlices_impl.hpp"
#include "render_impl.hpp"
#include "msbgaux_impl.hpp"
#include "mm_impl.hpp"
#include "mm2_impl.hpp"

#ifdef __cplusplus
#undef register
#endif

#endif // MSBG_HEADER_ONLY_HPP

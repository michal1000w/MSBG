#ifndef MGWin_H
#define MGWin_H

#include "globdef.h"
#include "bitmap.h"

MSBG_NAMESPACE_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

int MGWmakebmp(BmpBitmap *bmp, 
    	       int NB, int IW, int IH, int IBC, float gmax,
	       int chan, int ichan, int do_norm, int do_ignore_nan,
	       BmpRectangle *roi,
	       int *p_rr );
int MGWsetbmp(BmpBitmap *bmp,int NB, float W, float H, int MX, int ITR, int IOF);
int MGWputbmp(BmpBitmap *bmp,int NB, float X, float Y, int IBK);
int MGWdelbmp(int NM);

#ifdef __cplusplus
}
#endif

MSBG_NAMESPACE_END

#endif /* MGWin_H */

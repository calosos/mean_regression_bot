#include "wick_trace_mock.hpp"
int sma_handle=99;
double InpATRDeviationThreshold=1.5;
enum ReentryState{NONE,WAIT_BUY_REENTRY,WAIT_SELL_REENTRY};ReentryState reentry_state=NONE;
datetime reentry_outer_bar=0;
double deviation_prep_close=0,deviation_prep_sma=0,deviation_prep_atr=0,deviation_prep_d=0;

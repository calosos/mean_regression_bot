#include "signal_trace_mock.hpp"
#include <cmath>
#include <algorithm>
enum Strategy{ORIGINAL,BB_REENTRY,BB_WICK_REJECTION,ATR_DEVIATION_REENTRY};Strategy InpStrategy=BB_WICK_REJECTION;
const double EMPTY_VALUE=1.7976931348623157e308;
double InpWickMinRatio=.4;int atr_handle=1,state=0;const int CLOSING_IDEA=2;
datetime g_last_signal_bar=1200,processed_buy=0,processed_sell=0;
int opened=0;MqlRates source_candle={900,180,195,170,185};
bool MathIsValidNumber(double v){return std::isfinite(v);}double MathAbs(double v){return std::abs(v);}
double MathMin(double a,double b){return std::min(a,b);}double MathMax(double a,double b){return std::max(a,b);}
datetime iTime(const string&,int,int){return g_last_signal_bar;}
int CopyRates(const string&,int,int shift,int,MqlRates (&out)[1]){assert(shift==1);out[0]=source_candle;return 1;}
bool Bands(int shift,double &mid,double &upper,double &lower){assert(shift==1);mid=200;upper=220;lower=180;return true;}
double trace_atr=2;
bool Value(int handle,int,int shift,double &value){assert(shift==1);value=handle==99 ? 200:trace_atr;return true;}
bool SaveSignal(){return true;}void OpenIdea(int,double atr,double mid,double,double){assert(atr==trace_atr && mid==200);opened++;}
void TrackCurrent(){}void CloseStep(){}
void Log(const string &tag,const string &message,bool essential){if(essential || detailed)logs.push_back(tag+" "+message);}

#include "single_entry_mock.hpp"
enum SignalMode{INTRABAR,CLOSED_BAR};SignalMode InpSignalMode=INTRABAR;
enum Oscillator{STOCHASTIC,RSI};Oscillator InpOscillator=STOCHASTIC;
enum ReentryState{NONE,WAIT_BUY_REENTRY,WAIT_SELL_REENTRY};ReentryState reentry_state=NONE;
using ENUM_ACCOUNT_MARGIN_MODE=int;
const int MQL_TESTER=1,ACCOUNT_CURRENCY=1,ACCOUNT_MARGIN_MODE=2,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING=2;
const int INIT_FAILED=-1,INIT_PARAMETERS_INCORRECT=-2,INIT_SUCCEEDED=0,INVALID_HANDLE=-1;
const int SYMBOL_TRADE_TICK_SIZE=1,SYMBOL_VOLUME_MIN=2,SYMBOL_VOLUME_MAX=3,SYMBOL_VOLUME_STEP=4;
const int PRICE_CLOSE=0,MODE_SMA=0,STO_LOWHIGH=0;
int _Period=PERIOD_M5,InpBollingerPeriod=20,InpATRPeriod=14,InpRSIPeriod=14;
int InpStochasticK=14,InpStochasticD=3,InpStochasticSlowing=3;
double InpBollingerDeviation=2.5,InpRSIBuyLevel=30,InpRSISellLevel=70;
ulong InpMagicNumber=20261104,InpDeviationPoints=20;
int bands=INVALID_HANDLE,oscillator_handle=INVALID_HANDLE,atr_handle=INVALID_HANDLE;
int bands_created=0,atr_created=0,rsi_created=0,stoch_created=0,bb_period=0,atr_period=0;
double bb_deviation=0;bool tester=true,netting=false;
string currency="USD",signal_key="",exit_reason="";
datetime processed_buy=0,processed_sell=0,reentry_outer_bar=0,g_last_signal_bar=0;
template<class...T>void Print(T...){}
int MQLInfoInteger(int){return tester;}string AccountInfoString(int){return currency;}
int AccountInfoInteger(int){return ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;}
int StringFind(const string&s,const string&needle){auto pos=s.find(needle);return pos==string::npos ? -1:int(pos);}
double SymbolInfoDouble(const string&,int key){if(key==SYMBOL_TRADE_TICK_SIZE)return .01;if(key==SYMBOL_VOLUME_MIN)return .01;if(key==SYMBOL_VOLUME_MAX)return 100;return .01;}
string SignalKey(){return "test.";}bool GlobalVariableCheck(const string&){return false;}double GlobalVariableGet(const string&){return 0;}
int iBands(const string&,int,int period,int,double deviation,int){bands_created++;bb_period=period;bb_deviation=deviation;return 10;}
int iATR(const string&,int,int period){atr_created++;atr_period=period;return 11;}
int iRSI(const string&,int,int,int){rsi_created++;return 12;}
int iStochastic(const string&,int,int,int,int,int,int){stoch_created++;return 13;}
void TrackCurrent(){}datetime RecentOwnEnd(){return 0;}void Cooldown(datetime){}
// Wrap only CTrade configuration methods absent from the execution adapter.
struct InitTrade:FakeTrade{
 void SetExpertMagicNumber(ulong){}void SetDeviationInPoints(ulong){}void SetAsyncMode(bool){}void SetMarginMode(){}
}init_trade;
#define trade init_trade
void reset_init(){reset();bands_created=atr_created=rsi_created=stoch_created=0;bands=oscillator_handle=atr_handle=INVALID_HANDLE;
 InpStrategy=ORIGINAL;InpSignalMode=INTRABAR;InpOscillator=STOCHASTIC;InpStochasticK=14;InpStochasticD=3;InpStochasticSlowing=3;
 InpRSIPeriod=14;InpRSIBuyLevel=30;InpRSISellLevel=70;InpBollingerPeriod=20;InpBollingerDeviation=2.5;InpATRPeriod=14;InpTPFactor=.9;
 tester=true;currency="USD";reentry_state=WAIT_BUY_REENTRY;reentry_outer_bar=600;}

bool InpReentryWeekendGuard=false;
int InpWeekendEntryBlockMinutes=60,InpWeekendCloseMinutes=30;
bool g_weekend_close_due=false;
bool WeekendGuardEnabled(){return InpStrategy!=ORIGINAL && InpReentryWeekendGuard;}
void RefreshWeekendGuard(){}

void ResetWeekendGuard(){g_weekend_close_due=false;}

bool InpReentryMACDConfirm=false;
int InpMACDFast=12,InpMACDSlow=26,InpMACDSignal=9,macd_handle=INVALID_HANDLE,macd_created=0;
int iMACD(const string&,int timeframe,int fast,int slow,int signal,int price){assert(timeframe==PERIOD_M5 && fast>0 && fast<slow && signal>0 && price==PRICE_CLOSE);macd_created++;return 77;}

enum ReentryADXMode { ADX_OFF, ADX_BELOW_25, ADX_BELOW_20, ADX_BELOW_25_FALLING };
ReentryADXMode InpReentryADXMode=ADX_OFF;
int adx_handle=88;
int adx_created=0;
int iADX(const string&,int tf,int period){assert(tf==PERIOD_M5 && period==14);adx_created++;return 88;}

bool InpReentryBBWFilter=false;

enum ReentryBBWMode { BBW_NON_INCREASING, BBW_BELOW_P70 };
ReentryBBWMode InpReentryBBWMode=BBW_NON_INCREASING;

int sma_handle=INVALID_HANDLE,sma_created=0;
int iMA(const string&,int tf,int period,int shift,int method,int price){assert(tf==PERIOD_M5 && period==20 && shift==0 && method==MODE_SMA && price==PRICE_CLOSE);sma_created++;return 99;}

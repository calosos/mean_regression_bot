// Test-only MT5 adapters. No trading server or account connection.
#include <vector>
#include <algorithm>
#include <string>
#include <cassert>
#include <cmath>
#include <iostream>
using string=std::string;using datetime=long long;
enum Oscillator { STOCHASTIC, RSI };
Oscillator InpOscillator=STOCHASTIC;
double InpRSIBuyLevel=30,InpRSISellLevel=70,rsi_current=29,rsi_closed=29;
enum SignalMode { INTRABAR,CLOSED_BAR };
SignalMode InpSignalMode=INTRABAR;
enum Strategy { ORIGINAL, BB_REENTRY, BB_WICK_REJECTION, ATR_DEVIATION_REENTRY };
Strategy InpStrategy=ORIGINAL;
enum EAState { WAITING_SIGNAL,ACTIVE_IDEA,CLOSING_IDEA,COOLDOWN };
EAState state=WAITING_SIGNAL;
const int PERIOD_M5=5,TIME_DATE=1,TIME_SECONDS=2,POSITION_PROFIT=1,POSITION_SWAP=2;
string _Symbol="XAUUSD";
int oscillator_handle=10,atr_handle=11,direction=1;
bool manual_required=false,history_ok=true,had_exposure=false;
std::vector<int> pending;std::vector<ulong> position_ids;
ulong g_request_cycle=0,e1_order=0,e2_order=0;
datetime now=1000,g_last_signal_bar=900,cooldown_until=0,idea_start=0,tp_bar=0,processed_buy=0,processed_sell=0;
double closed_mid=200,closed_upper=220,closed_lower=180;
double g_sl=0,target=100,profit=0,k_current=9,k_closed=9,atr_closed=2;
int own_positions=0,own_orders=0,close_calls=0,reconcile_calls=0,problems=0,rejected_logs=0,signal_logs=0,tp_syncs=0;
bool foreign=false,accept_open=false,series_ready=true,rates_ready=true,closed_bands_ready=true,tp_bands_ready=true,stoch_ready=true,atr_ready=true;
struct MqlRates { datetime time;double low,high,close;double open=0; };
struct MqlTick { double bid,ask; };
MqlRates candles[3];
struct Entry {datetime time;double atr,mid,upper,lower;int side;};
std::vector<Entry> opens;
std::vector<int> band_reads,stoch_reads,atr_reads,rate_reads;
template<class T> int ArraySize(const std::vector<T>& a) {return a.size();}
template<class T> void ArrayResize(std::vector<T>& a,int n) {a.resize(n);}
datetime TimeCurrent(){return now;}
string TimeToString(datetime t,int){return std::to_string(t);}
template<class... T> string StringFormat(const char*,T...){return "";}
void PruneManagementRetries(){}void FlushExitReports(){}void ReconcilePending(){reconcile_calls++;}void CheckOwnership(){}
int OwnPositions(){return own_positions;}int OwnOrders(){return own_orders;}bool ForeignExposure(){return foreign;}
void TrackCurrent(){}void InspectIdeaHistory(){}string exit_reason="";void BeginClose(const string&reason){if(state!=CLOSING_IDEA)exit_reason=reason;state=CLOSING_IDEA;}
void CloseStep(){close_calls++;}void Problem(const string&){problems++;}
std::vector<string> event_tags;
void Log(const string &tag,const string&,bool=false){event_tags.push_back(tag);if(tag=="REJECTED")rejected_logs++;}
int PositionsTotal(){return own_positions;}ulong PositionGetTicket(int){return 1;}int PositionOwner(ulong){return 1;}
bool PositionSelectByTicket(ulong){return true;}double PositionGetDouble(int field){return field==POSITION_PROFIT ? profit:0;}
bool SymbolInfoTick(const string&,MqlTick &q){q.bid=100;q.ask=100.2;return true;}
#ifndef USE_REAL_TARGET
bool HitTarget(const MqlTick&){return false;}
#endif
bool SamePrice(double a,double b){return std::abs(a-b)<1e-9;}
#ifndef USE_REAL_TARGET
 double Target(double mid,double,double){return mid;}
#endif
double Budget(){return 62.5;}void SyncTP(){tp_syncs++;}
datetime iTime(const string&,int,int shift){return series_ready ? (shift>=3 ? candles[0].time-shift*300 : candles[shift].time):0;}
double bbw_mid2=100,bbw_upper2=120,bbw_lower2=80;bool bbw_bands2_ready=true;
const double EMPTY_VALUE=1.7976931348623157e308;
bool bbw_history=false;double history_mid[102],history_upper[102],history_lower[102];bool history_ready[102];
bool Bands(int shift,double &mid,double &upper,double &lower){band_reads.push_back(shift);if(bbw_history && shift>=2){mid=history_mid[shift];upper=history_upper[shift];lower=history_lower[shift];return history_ready[shift];}if(shift==2){mid=bbw_mid2;upper=bbw_upper2;lower=bbw_lower2;return bbw_bands2_ready;}mid=shift ? closed_mid:100;upper=shift ? closed_upper:110;lower=shift ? closed_lower:90;return shift ? closed_bands_ready:tp_bands_ready;}
bool InpReentryMACDConfirm=false;
int macd_handle=77;
double macd_values[2][3]={{0,-1,-2},{0,0,0}};
bool macd_ready[2][3]={{true,true,true},{true,true,true}};
std::vector<std::pair<int,int>> macd_reads;
bool MathIsValidNumber(double v){return std::isfinite(v);}
enum ReentryADXMode { ADX_OFF, ADX_BELOW_25, ADX_BELOW_20, ADX_BELOW_25_FALLING };
ReentryADXMode InpReentryADXMode=ADX_OFF;
int adx_handle=88;
double adx_values[3]={999,19,21};bool adx_ready[3]={true,true,true};
std::vector<int> adx_reads;
bool Value(int handle,int buffer,int shift,double &value){if(handle==99){assert(shift==1);value=closed_mid;return closed_bands_ready;}if(handle==adx_handle){assert(buffer==0);adx_reads.push_back(shift);value=adx_values[shift];return adx_ready[shift];}if(handle==macd_handle){macd_reads.push_back({buffer,shift});if(!macd_ready[buffer][shift])return false;value=macd_values[buffer][shift];return true;}if(handle==oscillator_handle){stoch_reads.push_back(shift);value=InpOscillator==RSI ? (shift ? rsi_closed:rsi_current) : (shift ? k_closed:k_current);return stoch_ready;}atr_reads.push_back(shift);value=atr_closed;return atr_ready;}
int CopyRates(const string&,int,int shift,int,MqlRates (&out)[1]){rate_reads.push_back(shift);out[0]=candles[shift];return rates_ready ? 1:0;}
bool SaveSignal(){return true;}
void SignalLog(int,const MqlRates&,double,double,double,double,double){signal_logs++;}
void OpenIdea(int side,double atr,double mid,double upper,double lower){opens.push_back({now,atr,mid,upper,lower,side});if(accept_open)state=ACTIVE_IDEA;}

void ObserveIdeaExcursions() {}
void ResetExcursions() {}

enum ReentryState { NONE, WAIT_BUY_REENTRY, WAIT_SELL_REENTRY };
ReentryState reentry_state=NONE;
datetime reentry_outer_bar=0;
int PeriodSeconds(int p){return p*60;}

bool InpReentryWeekendGuard=false;
int InpWeekendEntryBlockMinutes=60,InpWeekendCloseMinutes=30;
#ifndef WEEKEND_REAL
bool g_weekend_blocked=false;
bool WeekendGuardEnabled(){return InpStrategy!=ORIGINAL && InpReentryWeekendGuard;}
void RefreshWeekendGuard(){}void SuperviseWeekendClose(){}
#endif

bool InpReentryBBWFilter=false;

enum ReentryBBWMode { BBW_NON_INCREASING, BBW_BELOW_P70 };
ReentryBBWMode InpReentryBBWMode=BBW_NON_INCREASING;

double InpWickMinRatio=.40;

double MathMin(double a,double b){return std::min(a,b);}
double MathMax(double a,double b){return std::max(a,b);}
double MathAbs(double a){return std::abs(a);}

double InpATRDeviationThreshold=1.5;

int sma_handle=99;double deviation_prep_close=0,deviation_prep_sma=0,deviation_prep_atr=0,deviation_prep_d=0;

enum ReentryExitMode { EXIT_SMA20_DYNAMIC, EXIT_ATR_FIXED_2, EXIT_HALF_SMA20_DYNAMIC, EXIT_OPPOSITE_BAND_DYNAMIC, EXIT_HALF_SMA20_TRAIL_ATR };
ReentryExitMode InpReentryExitMode=EXIT_SMA20_DYNAMIC;

#include "partial_legacy_mock.hpp"

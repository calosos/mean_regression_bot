// Test-only MT5 adapters. No trading server or account connection.
#include <vector>
#include <string>
#include <cassert>
#include <cmath>
#include <iostream>
using string=std::string;using datetime=long long;
enum SignalMode { INTRABAR,CLOSED_BAR };
SignalMode InpSignalMode=INTRABAR;
enum EAState { WAITING_SIGNAL,ACTIVE_IDEA,CLOSING_IDEA,COOLDOWN };
EAState state=WAITING_SIGNAL;
const int PERIOD_M5=5,TIME_DATE=1,TIME_SECONDS=2,POSITION_PROFIT=1,POSITION_SWAP=2;
string _Symbol="XAUUSD";
int stoch=10,atr_handle=11,direction=1;
bool manual_required=false,history_ok=true,had_exposure=false;
std::vector<int> pending;std::vector<ulong> position_ids;
ulong g_request_cycle=0,e1_order=0,e2_order=0;
datetime now=1000,g_last_signal_bar=900,cooldown_until=0,idea_start=0,tp_bar=0,processed_buy=0,processed_sell=0;
double g_sl=0,target=100,profit=0,k_current=9,k_closed=9,atr_closed=2;
int own_positions=0,own_orders=0,close_calls=0,reconcile_calls=0,problems=0,rejected_logs=0,signal_logs=0,tp_syncs=0;
bool foreign=false,accept_open=false,series_ready=true,rates_ready=true,closed_bands_ready=true,tp_bands_ready=true,stoch_ready=true,atr_ready=true;
struct MqlRates { datetime time;double low,high,close; };
struct MqlTick { double bid,ask; };
MqlRates candles[2];
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
void TrackCurrent(){}void InspectIdeaHistory(){}void BeginClose(const string&){state=CLOSING_IDEA;}
void CloseStep(){close_calls++;}void Problem(const string&){problems++;}
void Log(const string &tag,const string&,bool=false){if(tag=="REJECTED")rejected_logs++;}
int PositionsTotal(){return own_positions;}ulong PositionGetTicket(int){return 1;}int PositionOwner(ulong){return 1;}
bool PositionSelectByTicket(ulong){return true;}double PositionGetDouble(int field){return field==POSITION_PROFIT ? profit:0;}
bool SymbolInfoTick(const string&,MqlTick &q){q.bid=100;q.ask=100.2;return true;}
bool HitTarget(const MqlTick&){return false;}bool SamePrice(double a,double b){return std::abs(a-b)<1e-9;}
double Target(double mid,double,double){return mid;}double Budget(){return 62.5;}void SyncTP(){tp_syncs++;}
void Cooldown(datetime t){cooldown_until=t/300*300+600;state=COOLDOWN;}
datetime iTime(const string&,int,int shift){return series_ready ? candles[shift].time:0;}
bool Bands(int shift,double &mid,double &upper,double &lower){band_reads.push_back(shift);mid=shift ? 200:100;upper=shift ? 220:110;lower=shift ? 180:90;return shift ? closed_bands_ready:tp_bands_ready;}
bool Value(int handle,int,int shift,double &value){if(handle==stoch){stoch_reads.push_back(shift);value=shift ? k_closed:k_current;return stoch_ready;}atr_reads.push_back(shift);value=atr_closed;return atr_ready;}
int CopyRates(const string&,int,int shift,int,MqlRates (&out)[1]){rate_reads.push_back(shift);out[0]=candles[shift];return rates_ready ? 1:0;}
bool SaveSignal(){return true;}
void SignalLog(int,const MqlRates&,double,double,double,double,double){signal_logs++;}
void OpenIdea(int side,double atr,double mid,double upper,double lower){opens.push_back({now,atr,mid,upper,lower,side});if(accept_open)state=ACTIVE_IDEA;}

void ObserveIdeaExcursions() {}
void ResetExcursions() {}

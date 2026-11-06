// Offline execution adapter: no terminal, trading account or production dependencies.
#include <vector>
#include <string>
#include <cmath>
#include <algorithm>
#include <cassert>
#include <iostream>
using string=std::string;using datetime=long long;using ENUM_ORDER_TYPE=int;
enum Strategy{ORIGINAL,BB_REENTRY,BB_WICK_REJECTION,ATR_DEVIATION_REENTRY};Strategy InpStrategy=BB_REENTRY;
enum EAState{WAITING_SIGNAL,ACTIVE_IDEA,CLOSING_IDEA,COOLDOWN};EAState state=WAITING_SIGNAL;
const int ORDER_TYPE_BUY=0,ORDER_TYPE_SELL=1,PERIOD_M5=5;
const int SYMBOL_TRADE_STOPS_LEVEL=1,SYMBOL_TRADE_FREEZE_LEVEL=2,SYMBOL_FILLING_MODE=3;
const int SYMBOL_FILLING_FOK=1,SYMBOL_FILLING_IOC=2,ORDER_FILLING_FOK=0,ORDER_FILLING_IOC=1,ORDER_FILLING_RETURN=2;
const int POSITION_VOLUME=1,POSITION_PRICE_OPEN=2,POSITION_SL=3,POSITION_TP=4,ORDER_PRICE_OPEN=5,ORDER_TP=6,ORDER_TIME_GTC=0;
const uint TRADE_RETCODE_DONE=10009,TRADE_RETCODE_DONE_PARTIAL=10010,TRADE_RETCODE_PLACED=10008,TRADE_RETCODE_TIMEOUT=10012,TRADE_RETCODE_INVALID_STOPS=10016,TRADE_RETCODE_NO_CHANGES=10025;
string _Symbol="XAUUSD";int _Digits=2,direction=1,entries=0;
double _Point=.01,tick_size=.01,volume_step=.01,volume_min=.01,volume_max=100;
double InpRiskBaseUSD=25000,InpRiskPercent=.25,InpATRMax=8,InpTPFactor=.9;
double frozen_atr=0,entry_price=0,lot=0,g_sl=0,target=0,realized=0;
datetime idea_start=0,tp_bar=0;ulong e1_order=0,e2_order=0;std::vector<ulong> position_ids;
bool manual_required=false,history_ok=true,had_exposure=false,foreign=false,fail_calc=false;
bool quote_ok=true;int quote_reads=0,quote_fail_at=0,calc_calls=0,calc_fail_at=0;
bool position=false;double pos_price=2500,pos_volume=0,pos_sl=0,pos_tp=0,quote_bid=2500,quote_ask=2500.2;
int buy_calls=0,sell_calls=0,pending_calls=0,modify_calls=0,locks=0,entry_logs=0;
uint entry_code=TRADE_RETCODE_DONE,modify_code=TRADE_RETCODE_DONE;
struct MqlTick{double bid,ask;};
template<class T>int ArraySize(const std::vector<T>&a){return a.size();}
template<class T>void ArrayResize(std::vector<T>&a,int n){a.resize(n);}
double MathAbs(double a){return std::abs(a);}double MathFloor(double a){return std::floor(a);}
double MathMin(double a,double b){return std::min(a,b);}double MathRound(double a){return std::round(a);}
double MathMax(double a,double b){return std::max(a,b);}bool MathIsValidNumber(double a){return std::isfinite(a);}
double NormalizeDouble(double a,int digits){double scale=std::pow(10,digits);return std::round(a*scale)/scale;}
bool OrderCalcProfit(int type,const string&,double vol,double from,double to,double &out){calc_calls++;if(fail_calc || calc_calls==calc_fail_at)return false;out=(type==ORDER_TYPE_BUY ? to-from:from-to)*vol*100;return true;}
#ifndef HALF_REAL
datetime TimeCurrent(){return 1202;}
#else
datetime partial_now=1202;datetime TimeCurrent(){return partial_now;}
#endif
datetime iTime(const string&,int,int){return 1200;}
long SymbolInfoInteger(const string&,int key){return key==SYMBOL_FILLING_MODE ? SYMBOL_FILLING_FOK:1;}
bool SymbolInfoTick(const string&,MqlTick&q){quote_reads++;q={quote_bid,quote_ask};return quote_ok && quote_reads!=quote_fail_at;}
void CheckOwnership(){}bool ForeignExposure(){return foreign;}int OwnPositions(){return position ? 1:0;}int OwnOrders(){return 0;}
int PositionsTotal(){return OwnPositions();}int OrdersTotal(){return 0;}
ulong PositionGetTicket(int){return 42;}int test_owner=1;int PositionOwner(ulong){return position ? test_owner:0;}bool PositionSelectByTicket(ulong){return position;}
double PositionGetDouble(int key){if(key==POSITION_VOLUME)return pos_volume;if(key==POSITION_PRICE_OPEN)return pos_price;if(key==POSITION_SL)return pos_sl;return pos_tp;}
ulong OrderGetTicket(int){return 0;}bool OwnOrder(){return false;}double OrderGetDouble(int){return 0;}
void ClearReentry(const string&){}void ResetExcursions(){}void ObserveIdeaExcursions(){}
void BeginClose(const string&){state=CLOSING_IDEA;}void Abort(const string&){state=CLOSING_IDEA;}
std::vector<string> entry_log_tags;
void Problem(const string&){}void Log(const string& tag,const string&,bool=false){entry_log_tags.push_back(tag);if(tag=="ENTRY")entry_logs++;}
template<class...T>string StringFormat(const char*,T...){return "";}
bool Uncertain(uint c){return c==TRADE_RETCODE_TIMEOUT || c==TRADE_RETCODE_PLACED;}
void LockResult(ulong,bool,bool){locks++;}bool Locked(ulong,bool){return locks>0;}
#ifndef HALF_REAL
bool ManagementRequestAllowed(ulong,bool){return true;}void RememberManagementResult(ulong,bool,uint){}
#endif
struct FakeTrade{
 uint code=TRADE_RETCODE_DONE;
 void SetTypeFilling(int){}
 bool market(double volume){code=entry_code;if(code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL){position=true;pos_volume=code==TRADE_RETCODE_DONE ? volume:volume/2;}return code==TRADE_RETCODE_DONE;}
 bool Buy(double v,const string&,int,int,int,const string&){buy_calls++;return market(v);}
 bool Sell(double v,const string&,int,int,int,const string&){sell_calls++;return market(v);}
 bool BuyLimit(double,double,const string&,double,double,int,int,const string&){pending_calls++;code=TRADE_RETCODE_PLACED;return true;}
 bool SellLimit(double,double,const string&,double,double,int,int,const string&){pending_calls++;code=TRADE_RETCODE_PLACED;return true;}
 void PositionModify(ulong,double sl,double tp){modify_calls++;code=modify_code;if(code==TRADE_RETCODE_INVALID_STOPS && tp==0)code=TRADE_RETCODE_DONE;if(code==TRADE_RETCODE_DONE){pos_sl=sl;pos_tp=tp;}}
 void OrderModify(ulong,double,double,double,int,int,int){}
 string ResultRetcodeDescription(){return "simulated";}
 uint ResultRetcode(){return code;}ulong ResultOrder(){return pending_calls ? 43:42;}
}trade;
extern double InpReentrySLATR;
enum ReentryExitMode { EXIT_SMA20_DYNAMIC, EXIT_ATR_FIXED_2, EXIT_HALF_SMA20_DYNAMIC, EXIT_OPPOSITE_BAND_DYNAMIC, EXIT_HALF_SMA20_TRAIL_ATR };
ReentryExitMode InpReentryExitMode=EXIT_SMA20_DYNAMIC;
void reset(){
 entry_log_tags.clear();
 InpReentryExitMode=EXIT_SMA20_DYNAMIC;
 InpReentrySLATR=3.0;
 InpStrategy=BB_REENTRY;state=WAITING_SIGNAL;manual_required=false;history_ok=true;foreign=false;had_exposure=false;fail_calc=false;
 quote_ok=true;quote_reads=quote_fail_at=calc_calls=calc_fail_at=0;position=false;pos_price=2500;pos_volume=pos_sl=pos_tp=0;quote_bid=2500;quote_ask=2500.2;
 buy_calls=sell_calls=pending_calls=modify_calls=locks=entry_logs=0;entry_code=modify_code=TRADE_RETCODE_DONE;
 InpRiskBaseUSD=25000;InpATRMax=8;g_sl=target=lot=0;entries=0;e1_order=e2_order=0;
}

double InpReentrySLATR=3.0;

double InpWickMinRatio=.40;

double InpATRDeviationThreshold=1.5;



#include "partial_legacy_mock.hpp"

const int POSITION_IDENTIFIER=10;
const int POSITION_TYPE=11,POSITION_TYPE_BUY=0,POSITION_TYPE_SELL=1;
long PositionGetInteger(int key){return key==POSITION_TYPE ? (direction>0 ? POSITION_TYPE_BUY:POSITION_TYPE_SELL):777;}

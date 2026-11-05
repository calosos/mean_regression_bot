// Test-only MT5 adapters. No trading server or account connection.
#include <vector>
#include <cmath>
#include <string>
#include <cassert>
#include <iostream>
using std::string;
using datetime=long long;
struct Obj { ulong id; bool own; bool mixed=false; };
std::vector<Obj> positions,orders;
std::vector<int> pending,position_ids;
ulong selected_order=0,selected_position=0;
uint forced_code=0;
int modify_calls=0,reconciliations=0;
bool manual_required=false,history_ok=true,had_exposure=false;
int fail_deletes=0,fail_closes=0,delete_calls=0,close_calls=0,cooldown_calls=0;
bool fill_on_delete=false;
const uint TRADE_RETCODE_DONE=10009,TRADE_RETCODE_DONE_PARTIAL=10010,TRADE_RETCODE_TIMEOUT=10012;
enum EAState { WAITING_SIGNAL, ACTIVE_IDEA, CLOSING_IDEA, COOLDOWN };
EAState state=CLOSING_IDEA;
datetime idea_start=1000;
ulong InpDeviationPoints=20;
string _Symbol="XAUUSD",exit_reason="test";
double realized=0;
int entries=1;
template<class T> int ArraySize(const std::vector<T>& v) { return v.size(); }
template<class T> void ArrayResize(std::vector<T>& v,int n) { v.resize(n); }
int PositionsTotal() { return positions.size(); }
int OrdersTotal() { return orders.size(); }
ulong PositionGetTicket(int i) { return positions[i].id; }
ulong OrderGetTicket(int i) { selected_order=orders[i].id; return selected_order; }
bool OwnOrder() { for(auto &o:orders) if(o.id==selected_order) return o.own; return false; }
int PositionOwner(ulong id) { for(auto &p:positions) if(p.id==id) return p.mixed ? 2 : p.own ? 1 : 0; return 0; }
int OwnPositions() { int n=0; for(auto &p:positions) n+=(p.own || p.mixed); return n; }
int OwnOrders() { int n=0; for(auto &o:orders) n+=o.own; return n; }
void ReconcilePending() { reconciliations++; }
void CheckOwnership() { for(auto &p:positions) if(p.mixed) manual_required=true; }
bool Locked(ulong,bool) { return !pending.empty(); }
bool Uncertain(uint code) { return code==TRADE_RETCODE_TIMEOUT; }
void LockResult(ulong,bool,bool) { pending.push_back(1); }
void Problem(const string&) {}
void Log(const string&,const string&,bool=false) {}
template<class... T> string StringFormat(const char*,T...) { return ""; }
void InspectIdeaHistory() {}
datetime now=1000;
datetime TimeCurrent() { return now; }
void Cooldown(datetime) { cooldown_calls++; state=COOLDOWN; }
struct FakeTrade {
 uint code=TRADE_RETCODE_DONE;
 void SetTypeFillingBySymbol(const string&) {}
 void OrderDelete(ulong id) {
  delete_calls++;
  if(forced_code) { code=forced_code; return; }
  if(fail_deletes-- > 0) { code=10018; return; }
  for(size_t i=0;i<orders.size();i++) if(orders[i].id==id) {
   if(fill_on_delete) { positions.push_back({88,true}); fill_on_delete=false; }
   orders.erase(orders.begin()+i); break;
  }
  code=TRADE_RETCODE_DONE;
 }
 void PositionClose(ulong id,ulong) {
  close_calls++;
  if(forced_code) { code=forced_code; return; }
  if(fail_closes-- > 0) { code=10018; return; }
  for(size_t i=0;i<positions.size();i++) if(positions[i].id==id) { positions.erase(positions.begin()+i); break; }
  code=TRADE_RETCODE_DONE;
 }
 void PositionModify(ulong,double,double) { modify_calls++; code=forced_code ? forced_code : TRADE_RETCODE_DONE; }
 void OrderModify(ulong,double,double,double,int,int,int) { modify_calls++; code=forced_code ? forced_code : TRADE_RETCODE_DONE; }
 uint ResultRetcode() { return code; }
 string ResultRetcodeDescription() { return "failed"; }
} trade;
void reset() {
 positions.clear(); orders.clear(); pending.clear();
 manual_required=false; history_ok=true; had_exposure=false;
 state=CLOSING_IDEA; fail_deletes=0; fail_closes=0; delete_calls=0; close_calls=0; cooldown_calls=0; fill_on_delete=false;
}

void QueueExitReport() {}
void FlushExitReports() {}

const uint TRADE_RETCODE_NO_CHANGES=10025,TRADE_RETCODE_MARKET_CLOSED=10018;
const int POSITION_SL=1,POSITION_TP=2,ORDER_PRICE_OPEN=3,ORDER_TP=4,ORDER_TIME_GTC=0;
double g_sl=2494,target=2499,quote_bid=2490,quote_ask=2490.2;
int direction=1;
struct MqlTick { double bid,ask; };
bool OrderSelect(ulong id) { for(auto &o:orders) if(o.id==id) { selected_order=id; return true; } return false; }
bool PositionSelectByTicket(ulong id) { for(auto &p:positions) if(p.id==id) { selected_position=id; return true; } return false; }
bool SymbolInfoTick(const string&,MqlTick &q) { q.bid=quote_bid; q.ask=quote_ask; return true; }
bool HitTarget(const MqlTick &q) { return direction>0 ? q.bid>=target : q.ask<=target; }
bool ValidTP(const MqlTick&) { return true; }
bool SamePrice(double a,double b) { return std::abs(a-b)<.001; }
double StopDistance() { return .01; }
double PositionGetDouble(int field) { return field==POSITION_SL ? g_sl : 0; }
double OrderGetDouble(int field) { return field==ORDER_PRICE_OPEN ? 2498 : 0; }
void BeginClose(const string&) { state=CLOSING_IDEA; }

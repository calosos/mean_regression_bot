// Test-only MT5 adapters. No trading server or account connection.
#include <vector>
#include <string>
#include <map>
#include <cmath>
#include <cassert>
#include <iostream>
#include <algorithm>
using string=std::string;
using datetime=long long;
using ENUM_ORDER_STATE=int;
using ENUM_DEAL_TYPE=int;
using ENUM_DEAL_ENTRY=int;
const int ORDER_STATE_FILLED=1,ORDER_STATE_CANCELED=2,ORDER_STATE_EXPIRED=3,ORDER_STATE_REJECTED=4;
const int DEAL_TYPE_BUY=1,DEAL_TYPE_SELL=2,DEAL_ENTRY_IN=1,DEAL_ENTRY_OUT=2,DEAL_ENTRY_OUT_BY=3,DEAL_ENTRY_INOUT=4;
const int ORDER_SYMBOL=1,ORDER_MAGIC=2,ORDER_STATE=3,ORDER_VOLUME_INITIAL=4,ORDER_VOLUME_CURRENT=5,ORDER_POSITION_ID=6;
const int DEAL_SYMBOL=1,DEAL_MAGIC=2,DEAL_ORDER=3,DEAL_POSITION_ID=4,DEAL_TYPE=5,DEAL_ENTRY=6,DEAL_VOLUME=7,DEAL_PROFIT=8,DEAL_SWAP=9,DEAL_COMMISSION=10,DEAL_FEE=11;
const int TIME_DATE=1,TIME_SECONDS=2;
string _Symbol="XAUUSD";
ulong InpMagicNumber=20261104;
bool netting=false,had_exposure=true,history_ok=true;
int entries=0;
double realized=0,volume_step=.01,lot=.03;
datetime idea_start=1790566264,now=1790566265;
ulong e1_order=100,e2_order=101;
std::vector<ulong> position_ids;
string exit_reason="Sin posiciones propias; cancelar residuales";
enum EAState { WAITING_SIGNAL,ACTIVE_IDEA,CLOSING_IDEA,COOLDOWN };
EAState state=ACTIVE_IDEA;
struct Deal { ulong ticket,order,id; int entry; double volume,pnl; ulong magic=20261104; double swap=0,commission=0,fee=0; string symbol="XAUUSD"; };
struct Order { double initial=.03,current=0; ulong id=0; int state=ORDER_STATE_FILLED; ulong magic=20261104; string symbol="XAUUSD"; };
std::vector<Deal> deals;
std::map<ulong,Order> orders;
bool history_available=true;
struct Captured { string tag; long idea; double pnl=0; int count=0; };
std::vector<Captured> logs;
template<class T> int ArraySize(const std::vector<T>& a) { return a.size(); }
template<class T> void ArrayResize(std::vector<T>& a,int n) { a.resize(n); }
template<class T> void ArrayCopy(std::vector<T>& a,const std::vector<T>& b) { a=b; }
template<class T> void ArrayInitialize(std::vector<T>& a,int v) { std::fill(a.begin(),a.end(),v); }
double MathAbs(double v) { return std::abs(v); }
datetime TimeCurrent() { return now; }
string TimeToString(datetime t,int) { return std::to_string(t); }
bool HistoryOrderSelect(ulong id) { return orders.count(id)>0; }
string HistoryOrderGetString(ulong id,int) { return orders.at(id).symbol; }
long HistoryOrderGetInteger(ulong id,int field) {
 auto &o=orders.at(id); if(field==ORDER_STATE) return o.state;
 if(field==ORDER_MAGIC) return o.magic; if(field==ORDER_POSITION_ID) return o.id; assert(false); return 0;
}
double HistoryOrderGetDouble(ulong id,int field) { return field==ORDER_VOLUME_INITIAL ? orders.at(id).initial : orders.at(id).current; }
bool HistorySelect(datetime,datetime) { return history_available; }
int HistoryDealsTotal() { return deals.size(); }
ulong HistoryDealGetTicket(int i) { return deals[i].ticket; }
Deal &get(ulong id) { for(auto &d:deals) if(d.ticket==id) return d; assert(false); return deals[0]; }
string HistoryDealGetString(ulong id,int) { return get(id).symbol; }
long HistoryDealGetInteger(ulong id,int field) {
 auto &d=get(id); switch(field) {
 case DEAL_MAGIC:return d.magic; case DEAL_ORDER:return d.order; case DEAL_POSITION_ID:return d.id;
 case DEAL_ENTRY:return d.entry; case DEAL_TYPE:return d.entry==DEAL_ENTRY_IN ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
 } assert(false); return 0;
}
double HistoryDealGetDouble(ulong id,int field) {
 auto &d=get(id); switch(field) {
 case DEAL_VOLUME:return d.volume; case DEAL_PROFIT:return d.pnl; case DEAL_SWAP:return d.swap;
 case DEAL_COMMISSION:return d.commission; case DEAL_FEE:return d.fee;
 } assert(false); return 0;
}
void PrintFormat(const char*,const string&,long id,const string&,const string&,double pnl,int count) { logs.push_back({"EXIT",id,pnl,count}); }
void PrintFormat(const char*,const string&,long id) { logs.push_back({"EXIT_PENDING",id}); }
void TrackCurrent() {}
void Problem(const string&) {}
void BeginClose(const string&) { state=CLOSING_IDEA; }
void Quarantine(const string&) { assert(false && "unexpected mixed active position"); }
bool Tracked(ulong);

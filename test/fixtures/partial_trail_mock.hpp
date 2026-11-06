#define HALF_REAL
#define Locked LegacyLocked
#define LockResult LegacyLockResult
#include "single_entry_mock.hpp"
#undef Locked
#undef LockResult
#include <map>
using ENUM_ORDER_STATE=int;using ENUM_DEAL_ENTRY=int;using ENUM_DEAL_TYPE=int;using ENUM_DEAL_REASON=int;using ENUM_POSITION_TYPE=int;
const uint TRADE_RETCODE_MARKET_CLOSED=10018;
const int DEAL_ORDER=20,DEAL_POSITION_ID=21,DEAL_REASON=22,DEAL_MAGIC=23,DEAL_ENTRY=24,DEAL_VOLUME=25,DEAL_SYMBOL=26,DEAL_TYPE=27,DEAL_COMMISSION=28,DEAL_FEE=29,DEAL_PROFIT=30,DEAL_SWAP=31;
const int DEAL_REASON_EXPERT=1,DEAL_REASON_SL=2,DEAL_ENTRY_IN=0,DEAL_ENTRY_OUT=1,DEAL_ENTRY_OUT_BY=2,DEAL_ENTRY_INOUT=3,DEAL_TYPE_BUY=0,DEAL_TYPE_SELL=1;
const int ORDER_SYMBOL=40,ORDER_MAGIC=41,ORDER_COMMENT=42,ORDER_STATE=43,ORDER_VOLUME_INITIAL=44,ORDER_VOLUME_CURRENT=45,TRADE_ACTION_DEAL=1;
const int ORDER_STATE_FILLED=1,ORDER_STATE_CANCELED=2,ORDER_STATE_REJECTED=3,ORDER_STATE_EXPIRED=4,ORDER_STATE_STARTED=5;
ulong InpMagicNumber=20261104,InpDeviationPoints=20;bool netting=false;
struct MqlTradeRequest{int action=0,type=0,type_filling=0;ulong position=0,magic=0,deviation=0;string symbol,comment;double volume=0,price=0;};
struct MqlTradeResult{uint retcode=0,request_id=0;ulong order=0,deal=0;};
struct HistOrder{ulong id;double requested,unfilled;string comment;int state;bool visible;};
struct HistDeal{ulong id,order,position;int entry,reason;double volume,profit=0,commission=0,fee=0,swap=0;};
std::vector<HistOrder> hist_orders;std::vector<HistDeal> hist_deals;
std::vector<ulong> g_half_orders;
int send_calls=0;uint send_code=TRADE_RETCODE_DONE;bool history_available=true,unknown_order=false;
MqlTradeRequest last_request;MqlTradeResult last_result;ulong serial=100;
void ResetLastError(){}
bool HistorySelect(datetime,datetime){return history_available;}
int HistoryOrdersTotal(){int n=0;for(auto&o:hist_orders)if(o.visible)n++;return n;}
ulong HistoryOrderGetTicket(int index){for(auto&o:hist_orders)if(o.visible && index--==0)return o.id;return 0;}
HistOrder *find_order(ulong id){for(auto&o:hist_orders)if(o.id==id)return &o;return nullptr;}
bool HistoryOrderSelect(ulong id){auto o=find_order(id);return history_available && o && o->visible;}
string HistoryOrderGetString(ulong id,int key){auto o=find_order(id);assert(o);return key==ORDER_SYMBOL ? _Symbol:o->comment;}
long HistoryOrderGetInteger(ulong id,int key){auto o=find_order(id);assert(o);return key==ORDER_MAGIC ? InpMagicNumber:o->state;}
double HistoryOrderGetDouble(ulong id,int key){auto o=find_order(id);assert(o);return key==ORDER_VOLUME_INITIAL ? o->requested:o->unfilled;}
int HistoryDealsTotal(){return hist_deals.size();}ulong HistoryDealGetTicket(int index){return hist_deals.at(index).id;}
HistDeal &find_deal(ulong id){for(auto&d:hist_deals)if(d.id==id)return d;assert(false);return hist_deals[0];}
string HistoryDealGetString(ulong,int){return _Symbol;}
long HistoryDealGetInteger(ulong id,int key){auto &d=find_deal(id);switch(key){case DEAL_ORDER:return d.order;case DEAL_POSITION_ID:return d.position;case DEAL_MAGIC:return InpMagicNumber;case DEAL_ENTRY:return d.entry;case DEAL_REASON:return d.reason;case DEAL_TYPE:return direction>0 ? DEAL_TYPE_BUY:DEAL_TYPE_SELL;}assert(false);return 0;}
double HistoryDealGetDouble(ulong id,int key){auto &d=find_deal(id);switch(key){case DEAL_VOLUME:return d.volume;case DEAL_PROFIT:return d.profit;case DEAL_COMMISSION:return d.commission;case DEAL_FEE:return d.fee;case DEAL_SWAP:return d.swap;}assert(false);return 0;}
void TrackCurrent(){}void TrackId(ulong){}bool Tracked(ulong id){return id==777;}
bool HalfExitMode();void ResetHalfExit();void HalfExitStep();void HalfExitTransaction(const MqlTradeRequest&,const MqlTradeResult&);
int ManagementRetryIndex(const ulong,const bool);bool ManagementRequestAllowed(ulong,bool);void RememberManagementResult(ulong,bool,uint);
void Quarantine(const string&){manual_required=true;state=CLOSING_IDEA;}
bool OrderSend(const MqlTradeRequest &request,MqlTradeResult &result){
 send_calls++;last_request=request;assert(request.position==42 && request.magic==InpMagicNumber && request.symbol==_Symbol);
 assert(request.type==(direction>0 ? ORDER_TYPE_SELL:ORDER_TYPE_BUY) && request.volume>0 && request.volume<pos_volume);
 result.retcode=send_code;result.request_id=send_calls;
 if(send_code==TRADE_RETCODE_DONE || send_code==TRADE_RETCODE_DONE_PARTIAL || send_code==TRADE_RETCODE_TIMEOUT){
  hist_orders.push_back({++serial,request.volume,request.volume,request.comment,ORDER_STATE_STARTED,false});
  if(!unknown_order)result.order=serial;
 }
 last_result=result;return true;
}
void settle(double amount,bool terminal=true,bool visible=true){
 assert(!hist_orders.empty());auto &o=hist_orders.back();o.visible=visible;o.unfilled=o.requested-amount;o.state=terminal ? (amount==o.requested ? ORDER_STATE_FILLED:ORDER_STATE_CANCELED):ORDER_STATE_STARTED;
 if(amount>0){hist_deals.push_back({1000+o.id,o.id,777,DEAL_ENTRY_OUT,DEAL_REASON_EXPERT,amount,10,-1,0,0});pos_volume-=amount;}
}

struct PendingRequest{uint id=0;ulong ticket=0,server_order=0;bool deletion=false,entry=false;};
std::vector<PendingRequest> pending;
void LockResult(ulong ticket,bool deletion,bool entry){locks++;PendingRequest p;p.ticket=ticket;p.deletion=deletion;p.entry=entry;pending.push_back(p);}
bool Locked(const ulong ticket,const bool deletion);

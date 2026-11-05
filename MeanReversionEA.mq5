#property strict
#property version "1.00"
#property description "Mean reversion MVP, Strategy Tester only, USD / M5"
#include <Trade/Trade.mqh>

enum SignalMode { INTRABAR, CLOSED_BAR };
input SignalMode InpSignalMode=INTRABAR;
input ulong  InpMagicNumber=20261104;
input double InpRiskBaseUSD=25000;
input double InpRiskPercent=0.25;
input int    InpBollingerPeriod=20;
input double InpBollingerDeviation=2.5;
input int    InpStochasticK=14;
input int    InpStochasticD=3;
input int    InpStochasticSlowing=3;
input int    InpATRPeriod=14;
input double InpATRMax=8;
input double InpTPFactor=0.90;
input ulong  InpDeviationPoints=20;
input bool   InpDetailedLogs=true;

enum EAState { WAITING_SIGNAL, ACTIVE_IDEA, CLOSING_IDEA, COOLDOWN };
EAState state=WAITING_SIGNAL;
CTrade trade;
int bands=INVALID_HANDLE,stoch=INVALID_HANDLE,atr_handle=INVALID_HANDLE;
bool netting=false,manual_required=false,history_ok=false,had_exposure=false;
double tick_size=0,volume_step=0,volume_min=0,volume_max=0;
double frozen_atr=0,entry_price=0,lot=0,g_sl=0,target=0;
int direction=0,entries=0;
datetime idea_start=0,cooldown_until=0,tp_bar=0;
datetime processed_buy=0,processed_sell=0;
datetime g_last_signal_bar=0;
ulong e1_order=0,e2_order=0;
ulong position_ids[];
string signal_key="";
string exit_reason="";
double realized=0;
// Reporting outlives the operational idea/cooldown: never reuse current idea
// globals to finish a previous idea's accounting after delayed history events.
struct ExitReport
{
   datetime idea_id;
   datetime closed_at;
   ulong first_order;
   ulong second_order;
   bool exposed;
   bool warned;
   string reason;
   ulong ids[];
};
ExitReport g_exit_reports[];
// Uncertain requests remain locked until server confirmation or disappearance
// of the referenced object. Never infer failure from elapsed time alone.
struct PendingRequest { uint id; ulong ticket; ulong server_order; bool deletion; bool entry; };
PendingRequest pending[];
datetime last_problem=0;
// Technical retry pacing only. Server/tester time, never Sleep or a session filter.
const int MANAGEMENT_RETRY_SECONDS=5;
struct ManagementRetry
{
   ulong ticket;
   bool order_object;
   datetime retry_after;
   ulong last_cycle;
};
ManagementRetry g_management_retries[];
ulong g_request_cycle=0;
datetime g_market_retry_after=0;

int ManagementRetryIndex(const ulong ticket,const bool order_object)
{
   for(int i=0;i<ArraySize(g_management_retries);i++)
      if(g_management_retries[i].ticket==ticket && g_management_retries[i].order_object==order_object) return i;
   int n=ArraySize(g_management_retries);
   ArrayResize(g_management_retries,n+1);
   g_management_retries[n].ticket=ticket;
   g_management_retries[n].order_object=order_object;
   g_management_retries[n].retry_after=0;
   g_management_retries[n].last_cycle=0;
   return n;
}
bool ManagementRequestAllowed(const ulong ticket,const bool order_object)
{
   if(TimeCurrent()<g_market_retry_after) return false;
   int i=ManagementRetryIndex(ticket,order_object);
   if(TimeCurrent()<g_management_retries[i].retry_after || g_management_retries[i].last_cycle==g_request_cycle) return false;
   // Shared by TP modification and closing/deletion of this same object.
   g_management_retries[i].last_cycle=g_request_cycle;
   return true;
}
void RememberManagementResult(const ulong ticket,const bool order_object,const uint code)
{
   int i=ManagementRetryIndex(ticket,order_object);
   g_management_retries[i].last_cycle=g_request_cycle;
   bool completed=(code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL || code==TRADE_RETCODE_NO_CHANGES);
   g_management_retries[i].retry_after=completed ? 0 : TimeCurrent()+MANAGEMENT_RETRY_SECONDS;
   // A market-closed rejection applies to the symbol, including its other tickets.
   if(code==TRADE_RETCODE_MARKET_CLOSED) g_market_retry_after=TimeCurrent()+MANAGEMENT_RETRY_SECONDS;
}
void PruneManagementRetries()
{
   for(int i=ArraySize(g_management_retries)-1;i>=0;i--)
   {
      bool exists=g_management_retries[i].order_object ? OrderSelect(g_management_retries[i].ticket) : PositionSelectByTicket(g_management_retries[i].ticket);
      if(exists) continue;
      for(int j=i;j<ArraySize(g_management_retries)-1;j++) g_management_retries[j]=g_management_retries[j+1];
      ArrayResize(g_management_retries,ArraySize(g_management_retries)-1);
   }
}

void Log(const string tag,const string message,const bool essential=false)
{
   if(essential || InpDetailedLogs)
      PrintFormat("%s %s idea=%I64d %s",tag,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),(long)idea_start,message);
}
void Problem(const string message)
{
   if(TimeCurrent()-last_problem>=30 || last_problem==0)
   { Log("ERROR",message,true); last_problem=TimeCurrent(); }
}
double Budget() { return InpRiskBaseUSD*InpRiskPercent/100.0; }
double Price(const double p) { return NormalizeDouble(MathRound(p/tick_size)*tick_size,_Digits); }
bool SamePrice(const double a,const double b) { return MathAbs(a-b)<tick_size*0.25; }
datetime BarOf(const datetime t) { return (datetime)((long)t/300*300); }
bool OwnOrder()
{
   return OrderGetString(ORDER_SYMBOL)==_Symbol && (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagicNumber;
}
// The selected position may have changed magic after an external netting deal.
// Inspect all deals attached to its immutable identifier before touching it.
int PositionOwner(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol) return 0;
   bool current_own=((ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber);
   if(!netting) return current_own ? 1 : 0;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(!HistorySelectByPosition(id))
   { history_ok=false; return -1; }
   bool ours=false,foreign=false;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)==InpMagicNumber) ours=true;
      else foreign=true;
   }
   if(!ours && current_own) return -1;
   if(ours && foreign)
   { Quarantine("Posicion netting mezclada: intervencion manual obligatoria"); return 2; }
   return ours ? 1 : 0;
}
void Quarantine(const string why)
{
   if(!manual_required) Log("MANUAL_REQUIRED",why+"; entradas bloqueadas; solo cancelar pendientes propias",true);
   manual_required=true;
   state=CLOSING_IDEA;
}
void CheckOwnership()
{
   history_ok=true;
   if(!netting) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int owner=PositionOwner(t);
      if(owner==2) Quarantine("Posicion netting mezclada: intervencion manual obligatoria");
      if(owner<0) { history_ok=false; Problem("No se puede verificar propiedad netting; gestion suspendida"); }
   }
}
int OwnPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      int owner=PositionOwner(t);
      if(owner==1 || owner==2) count++;
   }
   return count;
}
int OwnOrders()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--) { if(OrderGetTicket(i)>0 && OwnOrder()) count++; }
   return count;
}
bool ForeignExposure()
{
   if(!netting) return false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      PositionGetTicket(i);
      if(PositionGetString(POSITION_SYMBOL)==_Symbol) return true;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && !OwnOrder()) return true;
   return false;
}
void RemovePending(const int index)
{
   for(int j=index;j<ArraySize(pending)-1;j++) pending[j]=pending[j+1];
   ArrayResize(pending,ArraySize(pending)-1);
}
void RecoverEntryOrder(const int index)
{
   if(!pending[index].entry || pending[index].server_order!=0 || idea_start==0) return;
   ENUM_ORDER_TYPE expected=pending[index].deletion ?
      (direction>0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT) :
      (direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   ulong found=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t>0 && OwnOrder() && (datetime)OrderGetInteger(ORDER_TIME_SETUP)>=idea_start &&
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)==expected) { found=t; break; }
   }
   if(found==0 && HistorySelect(idea_start,TimeCurrent()))
   {
      for(int i=HistoryOrdersTotal()-1;i>=0;i--)
      {
         ulong t=HistoryOrderGetTicket(i);
         if(HistoryOrderGetString(t,ORDER_SYMBOL)==_Symbol && (ulong)HistoryOrderGetInteger(t,ORDER_MAGIC)==InpMagicNumber &&
            (ENUM_ORDER_TYPE)HistoryOrderGetInteger(t,ORDER_TYPE)==expected)
         { found=t; break; }
      }
   }
   if(found==0) return;
   pending[index].server_order=found;
   if(pending[index].deletion) e2_order=found; else e1_order=found;
}
void ReconcilePending()
{
   for(int i=ArraySize(pending)-1;i>=0;i--)
   {
      RecoverEntryOrder(i);
      if(pending[i].server_order!=0 && !OrderSelect(pending[i].server_order) && HistoryOrderSelect(pending[i].server_order))
      {
         ENUM_ORDER_STATE os=(ENUM_ORDER_STATE)HistoryOrderGetInteger(pending[i].server_order,ORDER_STATE);
         if(os==ORDER_STATE_FILLED || os==ORDER_STATE_CANCELED || os==ORDER_STATE_REJECTED || os==ORDER_STATE_EXPIRED)
         { RemovePending(i); continue; }
      }
      if(pending[i].entry) continue;
      bool exists=pending[i].deletion ? OrderSelect(pending[i].ticket) : PositionSelectByTicket(pending[i].ticket);
      if(!exists) RemovePending(i);
   }
}
bool Locked(const ulong ticket,const bool deletion)
{
   for(int i=0;i<ArraySize(pending);i++)
      if(!pending[i].entry && pending[i].ticket==ticket && pending[i].deletion==deletion) return true;
   return false;
}
bool Uncertain(const uint code)
{
   return code==TRADE_RETCODE_TIMEOUT || code==TRADE_RETCODE_CONNECTION || code==TRADE_RETCODE_PLACED || code==TRADE_RETCODE_LOCKED;
}
void LockResult(const ulong ticket,const bool deletion,const bool entry)
{
   MqlTradeResult r={}; trade.Result(r);
   int n=ArraySize(pending); ArrayResize(pending,n+1);
   pending[n].id=r.request_id; pending[n].ticket=ticket; pending[n].server_order=r.order;
   pending[n].deletion=deletion; pending[n].entry=entry;
   Log("REQUEST_PENDING",StringFormat("request=%u ticket=%I64u code=%u",r.request_id,ticket,r.retcode),true);
}
void BeginClose(const string why)
{
   if(state!=CLOSING_IDEA) { exit_reason=why; Log("EXIT_REQUEST",why,true); }
   state=CLOSING_IDEA;
}
void Abort(const string why)
{
   Log("REJECTED",why+"; servidor="+trade.ResultRetcodeDescription(),true);
   BeginClose(why);
}
void Cooldown(const datetime closed)
{
   cooldown_until=BarOf(closed)+600;
   state=COOLDOWN;
}
void CloseStep()
{
   ReconcilePending(); CheckOwnership();
   if(OwnPositions()>0 || OwnOrders()>0) had_exposure=true;
   // Cancel first: E2 may still fill while cancellations are being processed.
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t==0 || !OwnOrder() || Locked(t,true) || !ManagementRequestAllowed(t,true)) continue;
      trade.OrderDelete(t);
      uint code=trade.ResultRetcode();
      RememberManagementResult(t,true,code);
      if(Uncertain(code)) LockResult(t,true,false);
      else if(code!=TRADE_RETCODE_DONE) Problem("Cancelacion fallida: "+trade.ResultRetcodeDescription());
   }
   if(manual_required || !history_ok) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(PositionOwner(t)!=1 || Locked(t,false) || !ManagementRequestAllowed(t,false)) continue;
      trade.SetTypeFillingBySymbol(_Symbol);
      trade.PositionClose(t,InpDeviationPoints);
      uint code=trade.ResultRetcode();
      RememberManagementResult(t,false,code);
      if(Uncertain(code)) LockResult(t,false,false);
      else if(code!=TRADE_RETCODE_DONE && code!=TRADE_RETCODE_DONE_PARTIAL)
         Problem("Cierre fallido: "+trade.ResultRetcodeDescription());
   }
   CheckOwnership();
   if(!manual_required && history_ok && OwnPositions()==0 && OwnOrders()==0 && ArraySize(pending)==0)
   {
      InspectIdeaHistory();
      if(manual_required || !history_ok) return;
      QueueExitReport();
      FlushExitReports();
      if(had_exposure) Cooldown(TimeCurrent());
      else { state=WAITING_SIGNAL; idea_start=0; ArrayResize(position_ids,0); }
   }
}
bool Value(const int handle,const int buffer,const int shift,double &value)
{
   double a[1];
   if(CopyBuffer(handle,buffer,shift,1,a)!=1 || !MathIsValidNumber(a[0]) || a[0]==EMPTY_VALUE) return false;
   value=a[0]; return true;
}
bool Bands(const int shift,double &mid,double &upper,double &lower)
{
   return Value(bands,0,shift,mid) && Value(bands,1,shift,upper) && Value(bands,2,shift,lower);
}
double Target(const double mid,const double upper,const double lower)
{
   return Price(direction>0 ? lower+InpTPFactor*(mid-lower) : upper-InpTPFactor*(upper-mid));
}
bool Risk(const double volume,const double e1,const double e2,const double stop,double &risk)
{
   if(volume<=0 || stop<=0 || e2<=0 || (direction>0 ? !(stop<e2 && e2<e1) : !(stop>e2 && e2>e1))) return false;
   double a=0,b=0;
   ENUM_ORDER_TYPE type=direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,_Symbol,volume,e1,stop,a) || !OrderCalcProfit(type,_Symbol,volume,e2,stop,b)) return false;
   risk=-(a+b); return MathIsValidNumber(risk) && risk>0;
}
void Levels(const double e1,double &e2,double &stop)
{
   e2=Price(e1-direction*frozen_atr);
   stop=Price(e1-direction*3.0*frozen_atr);
}
bool Size(const double e1,double &volume)
{
   double e2,stop,risk;
   Levels(e1,e2,stop);
   if(!Risk(volume_min,e1,e2,stop,risk) || risk>Budget()) return false;
   double raw=volume_min*Budget()/risk;
   volume=NormalizeDouble(MathFloor(MathMin(raw,volume_max)/volume_step)*volume_step,8);
   while(volume>=volume_min)
   {
      if(!Risk(volume,e1,e2,stop,risk)) return false;
      if(risk<=Budget()) return true;
      volume=NormalizeDouble(volume-volume_step,8);
   }
   return false;
}
double StopDistance()
{
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(stops,freeze)*_Point;
}
bool HitTarget(const MqlTick &q) { return direction>0 ? q.bid>=target : q.ask<=target; }
bool ValidSL(const MqlTick &q)
{
   double distance=StopDistance();
   return direction>0 ? g_sl<q.bid && q.bid-g_sl>=distance : g_sl>q.ask && g_sl-q.ask>=distance;
}
bool ValidTP(const MqlTick &q)
{
   double distance=StopDistance();
   return direction>0 ? target>q.bid && target-q.bid>=distance : target<q.ask && q.ask-target>=distance;
}
// Remove an old broker TP when the new logical target cannot be installed.
// Otherwise the old TP could close the idea before the new target is reached.
void SyncTP()
{
   CheckOwnership(); if(manual_required || !history_ok) return;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   if(HitTarget(q)) { BeginClose("TP"); return; }
   double broker_tp=ValidTP(q) ? target : 0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(PositionOwner(t)!=1 || !PositionSelectByTicket(t)) continue;
      if(!SamePrice(PositionGetDouble(POSITION_SL),g_sl)) { BeginClose("SL comun ausente o alterado"); return; }
      if(SamePrice(PositionGetDouble(POSITION_TP),broker_tp)) continue;
      if(Locked(t,false) || !ManagementRequestAllowed(t,false)) continue;
      trade.PositionModify(t,g_sl,broker_tp);
      uint code=trade.ResultRetcode();
      RememberManagementResult(t,false,code);
      if(Uncertain(code)) LockResult(t,false,false);
      if(code==TRADE_RETCODE_DONE) Log("TP_UPDATE",StringFormat("posicion=%I64u objetivo=%.5f TP_servidor=%.5f resultado=%u",t,target,broker_tp,code));
      if(code!=TRADE_RETCODE_DONE && code!=TRADE_RETCODE_NO_CHANGES) Problem("TP pendiente de sincronizar: "+trade.ResultRetcodeDescription());
   }
   if(manual_required || !history_ok) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong t=OrderGetTicket(i);
      if(t==0 || !OwnOrder() || Locked(t,true)) continue;
      double p=OrderGetDouble(ORDER_PRICE_OPEN);
      double order_tp=broker_tp;
      if(order_tp!=0 && (direction>0 ? order_tp-p<StopDistance() : p-order_tp<StopDistance())) order_tp=0;
      if(SamePrice(OrderGetDouble(ORDER_TP),order_tp)) continue;
      if(!ManagementRequestAllowed(t,true)) continue;
      trade.OrderModify(t,p,g_sl,order_tp,ORDER_TIME_GTC,0,0);
      uint code=trade.ResultRetcode();
      RememberManagementResult(t,true,code);
      if(Uncertain(code)) LockResult(t,true,false);
      if(code==TRADE_RETCODE_DONE) Log("TP_UPDATE",StringFormat("orden=%I64u objetivo=%.5f resultado=%u",t,target,code));
      if(code!=TRADE_RETCODE_DONE && code!=TRADE_RETCODE_NO_CHANGES) Problem("TP de E2 pendiente de sincronizar");
   }
}
bool SetInitialSL()
{
   CheckOwnership(); if(manual_required || !history_ok) return false;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q) || !ValidSL(q)) return false;
   double tp=(!HitTarget(q) && ValidTP(q)) ? target : 0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(PositionOwner(t)!=1) continue;
      trade.PositionModify(t,g_sl,tp);
      uint code=trade.ResultRetcode();
      if(code==TRADE_RETCODE_INVALID_STOPS && tp!=0)
      {
         trade.PositionModify(t,g_sl,0);
         code=trade.ResultRetcode();
      }
      // Include the initial protection request in pacing if it aborts into
      // CloseStep in this same tick. The INVALID_STOPS fallback above sends a
      // different payload (SL without TP), not a duplicate retry.
      RememberManagementResult(t,false,code);
      if(Uncertain(code)) LockResult(t,false,false);
      if(!PositionSelectByTicket(t) || !SamePrice(PositionGetDouble(POSITION_SL),g_sl)) return false;
   }
   int count=OwnPositions();
   return !manual_required && history_ok && count>0;
}
int SignalSide(const double low,const double high,const double lower,const double upper,const double k,
               const datetime bar)
{
   if(low<=lower && k<10 && processed_buy!=bar) return 1;
   if(high>=upper && k>90 && processed_sell!=bar) return -1;
   return 0;
}
// Consume the new-bar opportunity before any active idea/cooldown early return.
// Use tick/server M5 time so unavailable series cannot create a late opportunity.
bool TakeClosedBarOpportunity()
{
   datetime current_bar=BarOf(TimeCurrent());
   datetime previous=g_last_signal_bar;
   g_last_signal_bar=current_bar;
   return previous!=0 && current_bar>previous;
}
int ClosedSignalSide(const MqlRates &candle,const double lower,const double upper,const double k)
{
   if(candle.close<=lower || candle.close>=upper) return 0;
   return SignalSide(candle.low,candle.high,lower,upper,k,candle.time);
}
void SignalLog(const int side,const MqlRates &candle,const double mid,const double upper,const double lower,
               const double k,const double atr_value)
{
   if(InpSignalMode==CLOSED_BAR)
   {
      // Log the exact shift=1 snapshot already used for confirmation. Reading
      // a market quote is observational only; failure must not reject a signal.
      datetime evaluated=TimeCurrent();
      datetime nominal_close=candle.time+PeriodSeconds(PERIOD_M5);
      long elapsed=(long)evaluated-(long)nominal_close;
      bool inside=(candle.close>lower && candle.close<upper);
      MqlTick quote={};
      string market="mercado_disponible=false";
      if(SymbolInfoTick(_Symbol,quote))
         market=StringFormat("mercado_disponible=true mercado_tick=%s mercado_bid=%.5f mercado_ask=%.5f mercado_referencia_e1=%.5f",
                TimeToString(quote.time,TIME_DATE|TIME_SECONDS),quote.bid,quote.ask,side>0 ? quote.ask : quote.bid);
      Log("SIGNAL",StringFormat("modo=CLOSED_BAR evaluacion=%s vela=%s cierre_nominal=%s segundos_desde_cierre=%I64d direccion=%s "
          "Open=%.5f High=%.5f Low=%.5f Close=%.5f LowerBand=%.10f SMA20=%.10f UpperBand=%.10f K=%.10f ATR=%.10f cierre_dentro_bandas=%s %s",
          TimeToString(evaluated,TIME_DATE|TIME_SECONDS),TimeToString(candle.time,TIME_DATE|TIME_SECONDS),
          TimeToString(nominal_close,TIME_DATE|TIME_SECONDS),elapsed,side>0 ? "BUY" : "SELL",
          candle.open,candle.high,candle.low,candle.close,lower,mid,upper,k,atr_value,inside ? "true" : "false",market));
      return;
   }
   Log("SIGNAL",StringFormat("modo=%s vela=%s direccion=%s precio=%.5f low=%.5f high=%.5f BB=%.5f/%.5f/%.5f K=%.5f ATR=%.5f",
       InpSignalMode==INTRABAR ? "INTRABAR" : "CLOSED_BAR",TimeToString(candle.time,TIME_DATE|TIME_SECONDS),
       side>0 ? "BUY" : "SELL",candle.close,candle.low,candle.high,lower,mid,upper,k,atr_value));
}
void EvaluateClosedBarSignal()
{
   MqlRates candle[1];
   double mid,upper,lower,k,atr_value;
   if(iTime(_Symbol,PERIOD_M5,0)!=g_last_signal_bar || CopyRates(_Symbol,PERIOD_M5,1,1,candle)!=1 ||
      candle[0].time>=g_last_signal_bar || !Bands(1,mid,upper,lower) || !Value(stoch,0,1,k) ||
      !Value(atr_handle,0,1,atr_value))
   {
      Log("REJECTED","modo=CLOSED_BAR nueva_vela="+TimeToString(g_last_signal_bar,TIME_DATE|TIME_SECONDS)+
          " datos no disponibles; oportunidad descartada sin reintento tardio",true);
      return;
   }
   int side=ClosedSignalSide(candle[0],lower,upper,k);
   if(side==0) return;
   // Signal confirmation uses shift=1; initial TP deliberately still uses shift=0.
   double tp_mid,tp_upper,tp_lower;
   if(!Bands(0,tp_mid,tp_upper,tp_lower))
   {
      Log("REJECTED","modo=CLOSED_BAR vela="+TimeToString(candle[0].time,TIME_DATE|TIME_SECONDS)+
          " bandas TP inicial no disponibles; oportunidad descartada",true);
      return;
   }
   if(side>0) processed_buy=candle[0].time;
   if(side<0) processed_sell=candle[0].time;
   if(!SaveSignal()) return;
   SignalLog(side,candle[0],mid,upper,lower,k,atr_value);
   OpenIdea(side,atr_value,tp_mid,tp_upper,tp_lower);
   TrackCurrent();
   if(state==CLOSING_IDEA) CloseStep();
}
bool ATRAllowed(const double value) { return value>0 && value<=InpATRMax; }
void OpenIdea(const int side,const double atr_value,const double mid,const double upper,const double lower)
{
   direction=side; frozen_atr=atr_value;
   if(!ATRAllowed(frozen_atr)) { Log("REJECTED","ATR fuera de rango"); return; }
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   if(!Size(side>0 ? q.ask : q.bid,lot)) { Log("REJECTED","Calculo de riesgo o lote insuficiente"); return; }
   CheckOwnership();
   if(manual_required || !history_ok || ForeignExposure() || OwnPositions()>0 || OwnOrders()>0) return;
   idea_start=TimeCurrent(); realized=0; entries=0; e1_order=0; e2_order=0; had_exposure=false;
   ArrayResize(position_ids,0);
   target=Target(mid,upper,lower); tp_bar=iTime(_Symbol,PERIOD_M5,0);
   state=ACTIVE_IDEA;
   // FOK when available; otherwise IOC, with partial execution handled by abort.
   long filling=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK)!=0) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC)!=0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);
   bool sent=side>0 ? trade.Buy(lot,_Symbol,0,0,0,"MR E1") : trade.Sell(lot,_Symbol,0,0,0,"MR E1");
   uint code=trade.ResultRetcode(); e1_order=trade.ResultOrder();
   if(Uncertain(code)) { LockResult(e1_order,false,true); Abort("E1 incierta"); return; }
   if(!sent || code!=TRADE_RETCODE_DONE)
   { Abort(code==TRADE_RETCODE_DONE_PARTIAL ? "E1 parcial" : "E1 rechazada"); return; }
   entry_price=0; double executed=0;
   CheckOwnership();
   if(manual_required || !history_ok) { Abort("Propiedad incierta tras E1"); return; }
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(PositionOwner(t)!=1 || !PositionSelectByTicket(t)) continue;
      double v=PositionGetDouble(POSITION_VOLUME);
      executed+=v; entry_price+=v*PositionGetDouble(POSITION_PRICE_OPEN);
   }
   if(executed>0) entry_price/=executed;
   if(entry_price<=0 || MathAbs(executed-lot)>volume_step*0.1)
   { Abort("E1 volumen parcial o precio desconocido"); return; }
   entries=1; had_exposure=true;
   double e2,risk;
   Levels(entry_price,e2,g_sl);
   if(!Risk(executed,entry_price,e2,g_sl,risk) || risk>Budget())
   { Abort("Riesgo real excedido o calculo fallido"); return; }
   if(!SetInitialSL()) { Abort("No se pudo establecer SL valido"); return; }
   if(!SymbolInfoTick(_Symbol,q)) { Abort("Sin cotizacion despues de E1"); return; }
   if(HitTarget(q)) { BeginClose("TP inicial alcanzado"); return; }
   if(direction>0 ? q.ask-e2<StopDistance() || e2>=q.ask : e2-q.bid<StopDistance() || e2<=q.bid)
   { Abort("E2 stops invalidos"); return; }
   double tp=ValidTP(q) ? target : 0;
   if(tp!=0 && (direction>0 ? tp-e2<StopDistance() : e2-tp<StopDistance())) tp=0;
   CheckOwnership(); if(manual_required || !history_ok) { Abort("Propiedad no verificable"); return; }
   // Pending orders use RETURN as prescribed by MT5, independently of market filling.
   trade.SetTypeFilling(ORDER_FILLING_RETURN);
   sent=direction>0 ? trade.BuyLimit(lot,e2,_Symbol,g_sl,tp,ORDER_TIME_GTC,0,"MR E2") : trade.SellLimit(lot,e2,_Symbol,g_sl,tp,ORDER_TIME_GTC,0,"MR E2");
   code=trade.ResultRetcode(); e2_order=trade.ResultOrder();
   if(Uncertain(code) && code!=TRADE_RETCODE_PLACED) { LockResult(e2_order,true,true); Abort("E2 incierta"); return; }
   if(!sent || (code!=TRADE_RETCODE_DONE && code!=TRADE_RETCODE_PLACED))
   { Abort("Colocacion E2 fallida"); return; }
   Log("ENTRY",StringFormat("E1=%.5f E1_orden=%I64u E2=%.5f E2_orden=%I64u lote=%.8f SL=%.5f TP=%.5f riesgo=%.2f",entry_price,e1_order,e2,e2_order,lot,g_sl,target,risk),true);
}

void TrackId(const ulong id)
{
   if(id==0 || Tracked(id)) return;
   int n=ArraySize(position_ids); ArrayResize(position_ids,n+1); position_ids[n]=id;
}
bool Tracked(const ulong id)
{
   for(int i=0;i<ArraySize(position_ids);i++) if(position_ids[i]==id) return true;
   return false;
}
void TrackCurrent()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(PositionOwner(t)!=1 || !PositionSelectByTicket(t)) continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      TrackId(id);
   }
}
// Rebuild from server history rather than relying on transaction arrival order.
// Only this idea's order/position identifiers may trigger its lifecycle rules.
void InspectIdeaHistory()
{
   if(idea_start==0) return;
   TrackCurrent();
   if(!HistorySelect(idea_start,TimeCurrent()))
   { history_ok=false; Problem("Historial de idea no disponible"); return; }
   // Discover all entry position IDs before summing any exits. E2 may have
   // opened and closed between ticks, and history enumeration need not match
   // transaction callback order (including deals in the very same second).
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagicNumber) continue;
      ulong order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
      if((e1_order!=0 && order==e1_order) || (e2_order!=0 && order==e2_order))
         TrackId((ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID));
   }
   double e2_volume=0; bool e1_seen=false,e2_seen=false;
   realized=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;
      ulong order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
      ulong id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);
      bool ours=(ulong)HistoryDealGetInteger(d,DEAL_MAGIC)==InpMagicNumber;
      bool belongs=Tracked(id) || (e1_order!=0 && order==e1_order) || (e2_order!=0 && order==e2_order);
      if(!belongs) continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      if(netting && !ours) { Quarantine("Deal ajeno sobre identificador de la idea netting"); continue; }
      if(!ours) continue;
      realized+=HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
      {
         realized+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP);
         if(state==ACTIVE_IDEA) BeginClose("Cierre detectado en historial de la idea");
      }
      if(order==e1_order && entry==DEAL_ENTRY_IN) e1_seen=true;
      if(order==e2_order && e2_order!=0 && entry==DEAL_ENTRY_IN)
      { e2_seen=true; e2_volume+=HistoryDealGetDouble(d,DEAL_VOLUME); }
   }
   entries=(e1_seen ? 1 : 0)+(e2_seen ? 1 : 0);
   if(e1_seen || e2_seen) had_exposure=true;
   if(state==ACTIVE_IDEA && e2_seen && e2_volume<lot-volume_step*0.1) BeginClose("E2 parcial");
}


// This code only reads history and emits logs. It never changes trading state,
// levels, cooldown, ownership decisions or retry deadlines.
bool ReportHasId(const ExitReport &report,const ulong id)
{
   for(int i=0;i<ArraySize(report.ids);i++) if(report.ids[i]==id) return true;
   return false;
}
void ReportAddId(ExitReport &report,const ulong id)
{
   if(id==0 || ReportHasId(report,id)) return;
   int n=ArraySize(report.ids); ArrayResize(report.ids,n+1); report.ids[n]=id;
}
void QueueExitReport()
{
   int n=ArraySize(g_exit_reports); ArrayResize(g_exit_reports,n+1);
   g_exit_reports[n].idea_id=idea_start;
   g_exit_reports[n].closed_at=TimeCurrent();
   g_exit_reports[n].first_order=e1_order;
   g_exit_reports[n].second_order=e2_order;
   g_exit_reports[n].exposed=had_exposure;
   g_exit_reports[n].warned=false;
   g_exit_reports[n].reason=exit_reason;
   ArrayResize(g_exit_reports[n].ids,ArraySize(position_ids));
   ArrayCopy(g_exit_reports[n].ids,position_ids);
}
bool ReportOrderVolume(ExitReport &report,const ulong order,double &executed)
{
   executed=0;
   if(order==0) return true;
   if(!HistoryOrderSelect(order)) return false;
   if(HistoryOrderGetString(order,ORDER_SYMBOL)!=_Symbol || (ulong)HistoryOrderGetInteger(order,ORDER_MAGIC)!=InpMagicNumber) return false;
   ENUM_ORDER_STATE os=(ENUM_ORDER_STATE)HistoryOrderGetInteger(order,ORDER_STATE);
   if(os!=ORDER_STATE_FILLED && os!=ORDER_STATE_CANCELED && os!=ORDER_STATE_EXPIRED && os!=ORDER_STATE_REJECTED) return false;
   if(os!=ORDER_STATE_REJECTED)
   {
      executed=HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL);
      if(os!=ORDER_STATE_FILLED) executed-=HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT);
      if(executed<0) return false;
   }
   if(executed>0) ReportAddId(report,(ulong)HistoryOrderGetInteger(order,ORDER_POSITION_ID));
   return true;
}
bool ReconcileExitReport(ExitReport &report,double &pnl,int &entry_count)
{
   pnl=0; entry_count=0;
   double expected_first=0,expected_second=0;
   if(!ReportOrderVolume(report,report.first_order,expected_first) ||
      !ReportOrderVolume(report,report.second_order,expected_second)) return false;
   // Full position lifetime is needed for restart cleanup too. Selection is
   // inclusive of the whole current second; no cursor based on DEAL_TIME.
   if(!HistorySelect(0,TimeCurrent())) return false;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagicNumber) continue;
      ulong order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
      if((report.first_order!=0 && order==report.first_order) || (report.second_order!=0 && order==report.second_order))
         ReportAddId(report,(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID));
   }
   double incoming[],outgoing[];
   ArrayResize(incoming,ArraySize(report.ids)); ArrayInitialize(incoming,0);
   ArrayResize(outgoing,ArraySize(report.ids)); ArrayInitialize(outgoing,0);
   ulong entry_orders[];
   double first_volume=0,second_volume=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;
      ulong id=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);
      if(!ReportHasId(report,id)) continue;
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(d,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      // A mixed netting position has no separable EA result. Do not fabricate it.
      if(netting && (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagicNumber) return false;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_INOUT) return false; // Reversals are outside this EA.
      double volume=HistoryDealGetDouble(d,DEAL_VOLUME);
      ulong order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
      for(int j=0;j<ArraySize(report.ids);j++)
      {
         if(report.ids[j]!=id) continue;
         if(entry==DEAL_ENTRY_IN) incoming[j]+=volume;
         else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) outgoing[j]+=volume;
      }
      if(entry==DEAL_ENTRY_IN)
      {
         if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagicNumber) return false;
         if(order==report.first_order) first_volume+=volume;
         if(order==report.second_order) second_volume+=volume;
         bool seen=false;
         for(int j=0;j<ArraySize(entry_orders);j++) if(entry_orders[j]==order) { seen=true; break; }
         if(!seen) { int n=ArraySize(entry_orders); ArrayResize(entry_orders,n+1); entry_orders[n]=order; }
      }
      pnl+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+
           HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
   }
   double tolerance=volume_step*0.1;
   if(MathAbs(first_volume-expected_first)>tolerance || MathAbs(second_volume-expected_second)>tolerance) return false;
   if(report.exposed && ArraySize(report.ids)==0) return false;
   for(int i=0;i<ArraySize(report.ids);i++)
      if(incoming[i]<=0 || MathAbs(incoming[i]-outgoing[i])>tolerance) return false;
   entry_count=ArraySize(entry_orders);
   return !report.exposed || entry_count>0;
}
void RemoveExitReport(const int index)
{
   // Copy fields explicitly because snapshots own independent dynamic ID arrays.
   for(int j=index;j<ArraySize(g_exit_reports)-1;j++)
   {
      g_exit_reports[j].idea_id=g_exit_reports[j+1].idea_id;
      g_exit_reports[j].closed_at=g_exit_reports[j+1].closed_at;
      g_exit_reports[j].first_order=g_exit_reports[j+1].first_order;
      g_exit_reports[j].second_order=g_exit_reports[j+1].second_order;
      g_exit_reports[j].exposed=g_exit_reports[j+1].exposed;
      g_exit_reports[j].warned=g_exit_reports[j+1].warned;
      g_exit_reports[j].reason=g_exit_reports[j+1].reason;
      ArrayResize(g_exit_reports[j].ids,ArraySize(g_exit_reports[j+1].ids));
      ArrayCopy(g_exit_reports[j].ids,g_exit_reports[j+1].ids);
   }
   ArrayResize(g_exit_reports,ArraySize(g_exit_reports)-1);
}
void FlushExitReports()
{
   for(int i=ArraySize(g_exit_reports)-1;i>=0;i--)
   {
      double pnl=0; int count=0;
      if(ReconcileExitReport(g_exit_reports[i],pnl,count))
      {
         PrintFormat("EXIT %s idea=%I64d cierre=%s motivo=%s PnL_realizado=%.2f entradas=%d",
                     TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),(long)g_exit_reports[i].idea_id,
                     TimeToString(g_exit_reports[i].closed_at,TIME_DATE|TIME_SECONDS),g_exit_reports[i].reason,pnl,count);
         RemoveExitReport(i);
      }
      else if(!g_exit_reports[i].warned)
      {
         PrintFormat("EXIT_PENDING %s idea=%I64d historial aun incompleto; resultado definitivo pendiente",
                     TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),(long)g_exit_reports[i].idea_id);
         g_exit_reports[i].warned=true;
      }
   }
}

datetime RecentOwnEnd()
{
   datetime result=0;
   if(!HistorySelect(TimeCurrent()-900,TimeCurrent())) { history_ok=false; return 0; }
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagicNumber) continue;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(d,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) continue;
      datetime time=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
      if(time>result) result=time;
   }
   for(int i=0;i<HistoryOrdersTotal();i++)
   {
      ulong o=HistoryOrderGetTicket(i);
      if(HistoryOrderGetString(o,ORDER_SYMBOL)!=_Symbol || (ulong)HistoryOrderGetInteger(o,ORDER_MAGIC)!=InpMagicNumber) continue;
      ENUM_ORDER_STATE os=(ENUM_ORDER_STATE)HistoryOrderGetInteger(o,ORDER_STATE);
      if(os!=ORDER_STATE_CANCELED && os!=ORDER_STATE_EXPIRED) continue;
      datetime time=(datetime)HistoryOrderGetInteger(o,ORDER_TIME_DONE);
      if(time>result) result=time;
   }
   return result;
}

// Terminal globals are standard MQL5 state, isolated by tester pass. They
// preserve consumed (including rejected) signals across reinitialization.
string SignalKey()
{
   uint hash=2166136261;
   for(int i=0;i<StringLen(_Symbol);i++) hash=(hash^(uint)StringGetCharacter(_Symbol,i))*16777619;
   return StringFormat("MR.%I64d.%08X.%I64u.",AccountInfoInteger(ACCOUNT_LOGIN),hash,InpMagicNumber);
}
bool SaveSignal()
{
   if(GlobalVariableSet(signal_key+"B",(double)processed_buy)==0 ||
      GlobalVariableSet(signal_key+"S",(double)processed_sell)==0)
   { Problem("No se pudo guardar la senal procesada; entrada descartada"); return false; }
   return true;
}

int OnInit()
{
   // This MVP is deliberately executable only inside the MT5 Strategy Tester.
   if(!MQLInfoInteger(MQL_TESTER))
   { Print("INIT_FAILED: EA exclusivo para el Probador de Estrategias; no operar en cuentas reales"); return INIT_FAILED; }
   if(AccountInfoString(ACCOUNT_CURRENCY)!="USD")
   { Print("INIT_FAILED: cuenta del probador debe estar denominada en USD"); return INIT_PARAMETERS_INCORRECT; }
   if(_Period!=PERIOD_M5 || StringFind(_Symbol,"XAUUSD")<0)
   { Print("INIT_FAILED: utilizar XAUUSD (se admiten prefijos/sufijos) en M5"); return INIT_PARAMETERS_INCORRECT; }
   if((InpSignalMode!=INTRABAR && InpSignalMode!=CLOSED_BAR) || InpMagicNumber==0 || !MathIsValidNumber(InpRiskBaseUSD) || InpRiskBaseUSD<=0 ||
      !MathIsValidNumber(InpRiskPercent) || InpRiskPercent<=0 || InpRiskPercent>100 ||
      InpBollingerPeriod<2 || !MathIsValidNumber(InpBollingerDeviation) || InpBollingerDeviation<=0 ||
      InpStochasticK<1 || InpStochasticD<1 || InpStochasticSlowing<1 || InpATRPeriod<1 ||
      !MathIsValidNumber(InpATRMax) || InpATRMax<=0 || !MathIsValidNumber(InpTPFactor) || InpTPFactor<=0 || InpTPFactor>1)
   { Print("INIT_FAILED: parametros invalidos"); return INIT_PARAMETERS_INCORRECT; }
   tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   volume_min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   volume_max=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   volume_step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(tick_size<=0 || volume_min<=0 || volume_step<=0 || volume_max<volume_min || !MathIsValidNumber(Budget()) || Budget()<=0)
      return INIT_FAILED;
   signal_key=SignalKey();
   if(InpSignalMode==CLOSED_BAR) signal_key+="C.";
   if(GlobalVariableCheck(signal_key+"B")) processed_buy=(datetime)GlobalVariableGet(signal_key+"B");
   if(GlobalVariableCheck(signal_key+"S")) processed_sell=(datetime)GlobalVariableGet(signal_key+"S");
   netting=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetMarginMode();
   bands=iBands(_Symbol,PERIOD_M5,InpBollingerPeriod,0,InpBollingerDeviation,PRICE_CLOSE);
   stoch=iStochastic(_Symbol,PERIOD_M5,InpStochasticK,InpStochasticD,InpStochasticSlowing,MODE_SMA,STO_LOWHIGH);
   atr_handle=iATR(_Symbol,PERIOD_M5,InpATRPeriod);
   if(bands==INVALID_HANDLE || stoch==INVALID_HANDLE || atr_handle==INVALID_HANDLE) return INIT_FAILED;
   g_last_signal_bar=BarOf(TimeCurrent()); // Do not evaluate a historical close on init/reinit.
   CheckOwnership();
   if(manual_required) return INIT_SUCCEEDED;
   if(!history_ok) { state=CLOSING_IDEA; exit_reason="Inicio con propiedad no verificable"; return INIT_SUCCEEDED; }
   if(OwnPositions()>0 || OwnOrders()>0)
   {
      had_exposure=true;
      idea_start=TimeCurrent(); TrackCurrent();
      BeginClose("Limpieza de residuos propios al iniciar");
   }
   else
   {
      datetime end=RecentOwnEnd();
      if(!history_ok) { state=CLOSING_IDEA; exit_reason="Historial inicial no disponible"; }
      else if(end>0 && BarOf(end)+600>TimeCurrent()) Cooldown(end);
   }
   Log("INIT",StringFormat("simbolo=%s cuenta=USD modelo=%s riesgo=%.2f",_Symbol,netting ? "netting" : "hedging",Budget()),true);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   FlushExitReports();
   if(bands!=INVALID_HANDLE) IndicatorRelease(bands);
   if(stoch!=INVALID_HANDLE) IndicatorRelease(stoch);
   if(atr_handle!=INVALID_HANDLE) IndicatorRelease(atr_handle);
}
void OnTick()
{
   bool closed_bar_tick=(InpSignalMode==CLOSED_BAR && TakeClosedBarOpportunity());
   g_request_cycle++;
   PruneManagementRetries();
   FlushExitReports();
   ReconcilePending(); CheckOwnership();
   if(!manual_required && history_ok && (state==WAITING_SIGNAL || state==COOLDOWN) && (OwnPositions()>0 || OwnOrders()>0))
   {
      idea_start=TimeCurrent(); had_exposure=true;
      e1_order=0; e2_order=0; ArrayResize(position_ids,0); TrackCurrent();
      BeginClose("Exposicion propia tardia fuera de una idea activa");
   }
   if(state==ACTIVE_IDEA || state==CLOSING_IDEA) InspectIdeaHistory();
   if(manual_required) { CloseStep(); return; }
   if(state==CLOSING_IDEA) { CloseStep(); return; }
   if(!history_ok) return;
   datetime bar=iTime(_Symbol,PERIOD_M5,0);
   if(bar==0)
   {
      if(closed_bar_tick) Log("REJECTED","modo=CLOSED_BAR serie M5 no disponible; oportunidad descartada",true);
      return;
   }
   if(state==COOLDOWN)
   {
      if(TimeCurrent()<cooldown_until) return;
      state=WAITING_SIGNAL;
      idea_start=0; ArrayResize(position_ids,0);
   }
   if(state==ACTIVE_IDEA)
   {
      if(OwnPositions()==0) { BeginClose("Sin posiciones propias; cancelar residuales"); CloseStep(); return; }
      MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
      double pnl=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
      {
         ulong t=PositionGetTicket(i);
         if(PositionOwner(t)!=1 || !PositionSelectByTicket(t)) continue;
         pnl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      }
      if(pnl<=-Budget()) BeginClose("Limite monetario flotante");
      else if(direction>0 ? q.bid<=g_sl : q.ask>=g_sl) BeginClose("SL comun");
      // First attempt the new candle target, so an obsolete target does not win.
      if(state==ACTIVE_IDEA && tp_bar!=bar)
      {
         double mid,upper,lower;
         if(Bands(1,mid,upper,lower))
         {
            double previous=target; target=Target(mid,upper,lower); tp_bar=bar;
            if(!SamePrice(previous,target)) Log("TP_UPDATE",StringFormat("anterior=%.5f nuevo=%.5f",previous,target));
         }
         else Problem("Indicadores TP no disponibles; mantener supervision y reintentar");
      }
      if(state==ACTIVE_IDEA && HitTarget(q)) BeginClose("TP dinamico");
      if(state==ACTIVE_IDEA) SyncTP();
      if(state==CLOSING_IDEA) CloseStep();
      return;
   }
   if(ArraySize(pending)>0 || OwnPositions()>0 || OwnOrders()>0 || ForeignExposure()) return;
   if(InpSignalMode==CLOSED_BAR)
   {
      if(closed_bar_tick) EvaluateClosedBarSignal();
      return;
   }
   double mid,upper,lower,k,atr_value;
   MqlRates current[1];
   if(!Bands(0,mid,upper,lower) || !Value(stoch,0,0,k) || !Value(atr_handle,0,1,atr_value) || CopyRates(_Symbol,PERIOD_M5,0,1,current)!=1)
   { Problem("REJECTED: indicadores no disponibles; senal no consumida"); return; }
   int side=SignalSide(current[0].low,current[0].high,lower,upper,k,bar);
   if(side>0) processed_buy=bar;
   if(side<0) processed_sell=bar;
   if(side==0 || !SaveSignal()) return;
   SignalLog(side,current[0],mid,upper,lower,k,atr_value);
   OpenIdea(side,atr_value,mid,upper,lower);
   TrackCurrent();
   if(state==CLOSING_IDEA) CloseStep();
}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type==TRADE_TRANSACTION_REQUEST)
   {
      for(int i=ArraySize(pending)-1;i>=0;i--)
      {
         if(pending[i].id==0 || result.request_id!=pending[i].id) continue;
         if(result.order!=0) pending[i].server_order=result.order;
         if(!pending[i].entry && !Uncertain(result.retcode))
            RememberManagementResult(pending[i].ticket,pending[i].deletion,result.retcode);
         // TIMEOUT / CONNECTION are final failure responses to this request.
         // The next tick reconciles live exposure before any retry.
         if(result.retcode!=TRADE_RETCODE_PLACED && result.retcode!=TRADE_RETCODE_LOCKED) RemovePending(i);
      }
   }
   if(trans.symbol!=_Symbol && trans.type!=TRADE_TRANSACTION_REQUEST) return;
   CheckOwnership();
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
   {
      ulong id=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
      ulong magic=(ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal,DEAL_TYPE);
      ulong order=(ulong)HistoryDealGetInteger(trans.deal,DEAL_ORDER);
      if(magic==InpMagicNumber && (state==ACTIVE_IDEA || state==CLOSING_IDEA) &&
         ((e1_order!=0 && order==e1_order) || (e2_order!=0 && order==e2_order))) TrackId(id);
      if(netting && magic!=InpMagicNumber && Tracked(id) && (type==DEAL_TYPE_BUY || type==DEAL_TYPE_SELL))
         Quarantine("Transaccion ajena sobre posicion netting de la idea");
   }
   ReconcilePending();
   if(state==ACTIVE_IDEA || state==CLOSING_IDEA) InspectIdeaHistory();
   FlushExitReports();
   // Execute reconciled actions on the next tick, not recursively in this handler.
}

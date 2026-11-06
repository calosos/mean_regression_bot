#property strict
#property version "1.00"
#property description "Mean reversion MVP, Strategy Tester only, USD / M5"
#include <Trade/Trade.mqh>

enum Strategy { ORIGINAL=0, BB_REENTRY=1, BB_WICK_REJECTION=2, ATR_DEVIATION_REENTRY=3 };
input Strategy InpStrategy=ORIGINAL;
input double InpWickMinRatio=0.40;
input double InpATRDeviationThreshold=1.5;
input double InpReentrySLATR=3.0;
enum ReentryExitMode { EXIT_SMA20_DYNAMIC=0, EXIT_ATR_FIXED_2=1, EXIT_HALF_SMA20_DYNAMIC=2, EXIT_OPPOSITE_BAND_DYNAMIC=3, EXIT_HALF_SMA20_TRAIL_ATR=4 };
input ReentryExitMode InpReentryExitMode=EXIT_SMA20_DYNAMIC;
input bool   InpReentryBBWFilter=false;
enum ReentryBBWMode { BBW_NON_INCREASING, BBW_BELOW_P70 };
input ReentryBBWMode InpReentryBBWMode=BBW_NON_INCREASING;
enum ReentryADXMode { ADX_OFF, ADX_BELOW_25, ADX_BELOW_20, ADX_BELOW_25_FALLING };
input ReentryADXMode InpReentryADXMode=ADX_OFF;
input bool   InpReentryMACDConfirm=false;
input int    InpMACDFast=12;
input int    InpMACDSlow=26;
input int    InpMACDSignal=9;
input bool   InpReentryWeekendGuard=false;
input int    InpWeekendEntryBlockMinutes=60;
input int    InpWeekendCloseMinutes=30;

enum Oscillator { STOCHASTIC, RSI };
input Oscillator InpOscillator=STOCHASTIC;
input int    InpRSIPeriod=14;
input double InpRSIBuyLevel=30;
input double InpRSISellLevel=70;

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
enum ReentryState { NONE, WAIT_BUY_REENTRY, WAIT_SELL_REENTRY };
ReentryState reentry_state=NONE;
datetime reentry_outer_bar=0;
double deviation_prep_close=0,deviation_prep_sma=0,deviation_prep_atr=0,deviation_prep_d=0;
struct WeeklySession { long begin; long end; };
bool g_weekend_valid=false,g_weekend_blocked=false,g_weekend_known=false,g_weekend_close_due=false;
datetime g_weekend_close=0,g_weekend_reopen=0,g_weekend_refresh=0,g_weekend_observed=0,g_weekend_missed=0;
string g_weekend_problem="";
CTrade trade;
int sma_handle=INVALID_HANDLE;
int adx_handle=INVALID_HANDLE;
int macd_handle=INVALID_HANDLE;
int bands=INVALID_HANDLE,oscillator_handle=INVALID_HANDLE,atr_handle=INVALID_HANDLE;
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
struct HalfExitState
{
   bool triggered,pending,trailing;
   double initial_volume,close_volume,extreme,requested_sl;
   ulong position_id,ticket,order;
   uint request_id,sequence;
   string comment;
};
HalfExitState g_half;
ulong g_half_orders[];
struct ExcursionStats
{
   long e1_msc;
   double mfe;
   double mae;
   datetime mfe_at;
   datetime mae_at;
   double risk_budget;
};
ExcursionStats g_excursions;
struct DiagnosticPosition
{
   ulong ticket;
   ulong id;
   double volume;
   double profit;
   double swap;
   long updated_msc;
};
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
   ExcursionStats excursions;
   long first_execution_msc;
   long last_exit_msc;
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
   if(HalfExitMode() && g_half.pending && !deletion)
   {
      if(ticket==g_half.ticket) return true;
      if(PositionSelectByTicket(ticket) && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==g_half.position_id) return true;
   }
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
void ClearReentry(const string reason)
{
   if(InpStrategy==ATR_DEVIATION_REENTRY && reentry_state!=NONE)
   {
      Log("PREPARATION_CLEAR",StringFormat("estrategia=ATR_DEVIATION_REENTRY direccion=%s vela=%s motivo=%s",
          reentry_state==WAIT_BUY_REENTRY ? "BUY" : "SELL",TimeToString(reentry_outer_bar,TIME_DATE|TIME_SECONDS),reason));
      reentry_state=NONE; reentry_outer_bar=0;
      deviation_prep_close=0; deviation_prep_sma=0; deviation_prep_atr=0; deviation_prep_d=0;
      return;
   }
   if(InpStrategy!=BB_REENTRY || reentry_state==NONE) return;
   Log("PREPARATION_CLEAR",StringFormat("estrategia=BB_REENTRY direccion=%s vela_exterior=%s motivo=%s",
       reentry_state==WAIT_BUY_REENTRY ? "BUY" : "SELL",
       TimeToString(reentry_outer_bar,TIME_DATE|TIME_SECONDS),reason));
   reentry_state=NONE;
   reentry_outer_bar=0;
}
void ResetWeekendGuard()
{
   g_weekend_valid=false; g_weekend_blocked=false; g_weekend_known=false; g_weekend_close_due=false;
   g_weekend_close=0; g_weekend_reopen=0; g_weekend_refresh=0; g_weekend_observed=0; g_weekend_missed=0;
   g_weekend_problem="";
}
bool WeekendGuardEnabled()
{
   return InpStrategy!=ORIGINAL && InpReentryWeekendGuard;
}
// Session dates are irrelevant; use time-of-day and the broker's weekday.
// Merge a repeated weekly pattern so overnight sessions and the Sunday seam
// are treated exactly like sessions within a day.
bool ReadWeeklyBreak(long &close_offset,long &open_offset,string &problem)
{
   WeeklySession spans[];
   ArrayResize(spans,0);
   for(int day=0;day<7;day++)
   {
      bool ended=false;
      for(uint index=0;index<128;index++)
      {
         datetime from=0,to=0;
         ResetLastError();
         if(!SymbolInfoSessionTrade(_Symbol,(ENUM_DAY_OF_WEEK)day,index,from,to))
         {
            int error=GetLastError();
            if(error!=0 && error!=ERR_MARKET_SESSION_INDEX)
            { problem=StringFormat("sesiones no disponibles dia=%d indice=%u error=%d",day,index,error); return false; }
            ended=true;
            break;
         }
         MqlDateTime start_time={},end_time={};
         if(!TimeToStruct(from,start_time) || !TimeToStruct(to,end_time))
         { problem="hora de sesion no interpretable"; return false; }
         long start=start_time.hour*3600+start_time.min*60+start_time.sec;
         long finish=end_time.hour*3600+end_time.min*60+end_time.sec;
         if(start==finish && start!=0)
         { problem="sesion con extremos iguales fuera de medianoche; duracion ambigua"; return false; }
         if(finish<=start) finish+=86400; // 00:00 end, overnight, or full 00:00-00:00 day.
         for(int repeat=-1;repeat<=1;repeat++)
         {
            int n=ArraySize(spans);
            ArrayResize(spans,n+1);
            spans[n].begin=day*86400+start+repeat*604800;
            spans[n].end=day*86400+finish+repeat*604800;
         }
      }
      if(!ended) { problem="demasiadas sesiones; horario incompleto"; return false; }
   }
   int count=ArraySize(spans);
   if(count==0) { problem="simbolo sin sesiones de trading disponibles"; return false; }
   for(int i=1;i<count;i++)
   {
      WeeklySession item=spans[i];
      int j=i-1;
      while(j>=0 && spans[j].begin>item.begin)
      { spans[j+1]=spans[j]; j--; }
      spans[j+1]=item;
   }
   long end=spans[0].end;
   int breaks=0;
   for(int i=1;i<count;i++)
   {
      if(spans[i].begin>end)
      {
         if(end>=0 && end<604800 && spans[i].begin-end>86400)
         { close_offset=end; open_offset=spans[i].begin; breaks++; }
         end=spans[i].end;
      }
      else if(spans[i].end>end) end=spans[i].end;
   }
   if(breaks!=1)
   { problem=StringFormat("descanso semanal no identificable: interrupciones superiores a 24h=%d",breaks); return false; }
   return true;
}
void RefreshWeekendGuard()
{
   if(!WeekendGuardEnabled()) return;
   datetime now=TimeCurrent();
   // Query changes at most once per server minute; boundary checks run every event.
   if(g_weekend_refresh==0 || now>=g_weekend_refresh || now<g_weekend_observed)
   {
      g_weekend_refresh=now+60;
      long close_offset=0,open_offset=0;
      string problem="";
      bool valid=ReadWeeklyBreak(close_offset,open_offset,problem);
      MqlDateTime clock={};
      if(valid && !TimeToStruct(now,clock)) { valid=false; problem="hora del servidor no interpretable"; }
      if(valid)
      {
         datetime sunday=now-clock.hour*3600-clock.min*60-clock.sec-clock.day_of_week*86400;
         datetime close_at=0,reopen_at=0;
         for(int week=-1;week<=1;week++)
         {
            datetime candidate_open=(datetime)((long)sunday+open_offset+(long)week*604800);
            if(candidate_open>now)
            {
               close_at=(datetime)((long)sunday+close_offset+(long)week*604800);
               reopen_at=candidate_open;
               break;
            }
         }
         if(reopen_at==0) { valid=false; problem="no se pudo proyectar la siguiente sesion semanal"; }
         else
         {
            // Before moving to a new week, report any missed prior deadline.
            if(g_weekend_valid && g_weekend_close!=0 && now>=g_weekend_close &&
               g_weekend_missed!=g_weekend_close && OwnPositions()>0)
            {
               Log("WEEKEND_EXPOSURE",StringFormat("cierre_semanal=%s queda exposicion; cierre no garantizado; mantener gestion y reintentos",
                   TimeToString(g_weekend_close,TIME_DATE|TIME_SECONDS)),true);
               g_weekend_missed=g_weekend_close;
               if(state==ACTIVE_IDEA) BeginClose("WEEKEND_GUARD");
            }
            if(!g_weekend_valid || close_at!=g_weekend_close || reopen_at!=g_weekend_reopen)
               Log("WEEKEND_SCHEDULE",StringFormat("cierre=%s reapertura=%s hora=servidor",
                   TimeToString(close_at,TIME_DATE|TIME_SECONDS),TimeToString(reopen_at,TIME_DATE|TIME_SECONDS)),true);
            g_weekend_close=close_at;
            g_weekend_reopen=reopen_at;
         }
      }
      if(!valid && (g_weekend_valid || problem!=g_weekend_problem))
         Log("WEEKEND_SCHEDULE_ERROR",problem+"; entradas bloqueadas; gestion existente conservada; sin hora supuesta",true);
      g_weekend_valid=valid;
      g_weekend_problem=problem;
   }
   g_weekend_observed=now;
   bool blocked=!g_weekend_valid ||
       (now>=(datetime)((long)g_weekend_close-(long)InpWeekendEntryBlockMinutes*60) && now<g_weekend_reopen);
   g_weekend_close_due=g_weekend_valid &&
       now>=(datetime)((long)g_weekend_close-(long)InpWeekendCloseMinutes*60) && now<g_weekend_reopen;
   if(g_weekend_valid && now>=g_weekend_close && now<g_weekend_reopen &&
      g_weekend_missed!=g_weekend_close && OwnPositions()>0)
   {
      Log("WEEKEND_EXPOSURE",StringFormat("cierre_semanal=%s queda exposicion; mantener cierre y reintentos",
          TimeToString(g_weekend_close,TIME_DATE|TIME_SECONDS)),true);
      g_weekend_missed=g_weekend_close;
   }
   if(!g_weekend_known || blocked!=g_weekend_blocked)
   {
      if(blocked || g_weekend_known)
         Log(blocked ? "WEEKEND_BLOCK_START" : "WEEKEND_BLOCK_END",
             g_weekend_valid ? "hora del servidor; preparacion reiniciada" : "horario no valido; preparacion reiniciada",true);
      ClearReentry(blocked ? "bloqueo semanal" : "fin de bloqueo semanal");
      // Never evaluate the bar that preceded the first event after reopening.
      if(g_weekend_known && !blocked) g_last_signal_bar=BarOf(now);
   }
   g_weekend_known=true;
   g_weekend_blocked=blocked;
   if(blocked) ClearReentry("bloqueo semanal");
   if(g_weekend_close_due && state==ACTIVE_IDEA) BeginClose("WEEKEND_GUARD");
}
// Closing gets the first management request of the tick. Remaining exposure
// retains logical SL/TP/risk supervision without changing the exit reason.
void SuperviseWeekendClose()
{
   if(!WeekendGuardEnabled() || state!=CLOSING_IDEA || exit_reason!="WEEKEND_GUARD" || manual_required || !history_ok) return;
   if(OwnPositions()==0) return;
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q)) return;
   double pnl=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(PositionOwner(ticket)!=1 || !PositionSelectByTicket(ticket)) continue;
      pnl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   if(pnl<=-Budget()) BeginClose("Limite monetario flotante");
   if(direction>0 ? q.bid<=g_sl : q.ask>=g_sl) BeginClose("SL comun");
   datetime bar=iTime(_Symbol,PERIOD_M5,0);
   if(!(InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_ATR_FIXED_2) && !(HalfExitMode() && g_half.trailing) && bar!=0 && tp_bar!=bar)
   {
      double mid,upper,lower;
      if(TargetInputs(1,mid,upper,lower))
      {
         double previous=target;
         target=Target(mid,upper,lower); tp_bar=bar;
         if(!SamePrice(previous,target)) Log("TP_UPDATE",StringFormat("anterior=%.5f nuevo=%.5f",previous,target));
      }
      else Problem("Indicadores TP no disponibles durante WEEKEND_GUARD; reintentar");
   }
   if(HalfExitMode()) return; // Whole-idea closing takes priority; never start another partial here.
   if(HitTarget(q)) BeginClose(InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_ATR_FIXED_2 ? "TP fijo" : "TP dinamico");
   SyncTP();
}

bool HalfExitMode()
{
   return InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_HALF_SMA20_TRAIL_ATR;
}
void ResetHalfExit()
{
   g_half.triggered=false; g_half.pending=false; g_half.trailing=false;
   g_half.initial_volume=0; g_half.close_volume=0; g_half.extreme=0; g_half.requested_sl=0;
   g_half.position_id=0; g_half.ticket=0; g_half.order=0; g_half.request_id=0; g_half.sequence=0; g_half.comment="";
   ArrayResize(g_half_orders,0);
}
bool HalfKnownOrder(const ulong order)
{
   if(order==0) return false;
   for(int i=0;i<ArraySize(g_half_orders);i++) if(g_half_orders[i]==order) return true;
   return false;
}
void HalfRememberOrder(const ulong order)
{
   if(order==0 || HalfKnownOrder(order)) return;
   int n=ArraySize(g_half_orders); ArrayResize(g_half_orders,n+1); g_half_orders[n]=order;
}
// SL/TP deals always retain their normal whole-idea exit semantics. Defer an
// unclassified own expert exit only while its partial request is unresolved.
bool IgnoreHalfDeal(const ulong deal)
{
   if(!HalfExitMode() || g_half.position_id==0) return false;
   if((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=g_half.position_id ||
      (ENUM_DEAL_REASON)HistoryDealGetInteger(deal,DEAL_REASON)!=DEAL_REASON_EXPERT) return false;
   return HalfKnownOrder((ulong)HistoryDealGetInteger(deal,DEAL_ORDER)) || (g_half.pending && g_half.order==0);
}
ulong HalfPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(PositionOwner(ticket)!=1 || !PositionSelectByTicket(ticket)) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER)==g_half.position_id) return ticket;
   }
   return 0;
}
bool HalfVolumeValid(const double volume)
{
   return MathIsValidNumber(volume) && volume>=volume_min && volume<=volume_max &&
          MathAbs(volume/volume_step-MathRound(volume/volume_step))<0.000001;
}
bool HalfSplit(const double initial,double &part)
{
   if(!HalfVolumeValid(initial)) return false;
   long steps=(long)MathRound(initial/volume_step);
   part=NormalizeDouble((steps/2)*volume_step,8);
   return HalfVolumeValid(part) && HalfVolumeValid(NormalizeDouble(initial-part,8));
}
void HalfExitTransaction(const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(!HalfExitMode() || !g_half.pending || request.magic!=InpMagicNumber || request.symbol!=_Symbol ||
      request.comment!=g_half.comment || request.position!=g_half.ticket) return;
   if(result.order!=0) { g_half.order=result.order; HalfRememberOrder(result.order); }
   // A timeout/connection result cannot prove that an order did not execute.
   if(g_half.order==0 && result.retcode!=0 && !Uncertain(result.retcode) && result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL)
   {
      g_half.pending=false;
      RememberManagementResult(g_half.ticket,false,result.retcode);
      Log("PARTIAL_REJECTED",StringFormat("request=%u code=%u; reintentar con volumen reconciliado",result.request_id,result.retcode),true);
   }
}
// No unlock based on elapsed time: recover the exact order by its unique
// comment/magic/symbol and wait for terminal history AND all of its deals.
bool ReconcileHalfExit(double &closed)
{
   closed=0;
   if(!HalfExitMode() || g_half.position_id==0) return true;
   if(!HistorySelect(idea_start,TimeCurrent())) { Problem("Parcial: historial no disponible; no reenviar"); return false; }
   if(g_half.pending && g_half.order==0)
   {
      for(int i=0;i<HistoryOrdersTotal();i++)
      {
         ulong order=HistoryOrderGetTicket(i);
         if(HistoryOrderGetString(order,ORDER_SYMBOL)==_Symbol &&
            (ulong)HistoryOrderGetInteger(order,ORDER_MAGIC)==InpMagicNumber &&
            HistoryOrderGetString(order,ORDER_COMMENT)==g_half.comment)
         { g_half.order=order; HalfRememberOrder(order); break; }
      }
   }
   bool terminal=true;
   for(int j=0;j<ArraySize(g_half_orders);j++)
   {
      ulong order=g_half_orders[j];
      if(!HistoryOrderSelect(order)) return false;
      ENUM_ORDER_STATE os=(ENUM_ORDER_STATE)HistoryOrderGetInteger(order,ORDER_STATE);
      if(os!=ORDER_STATE_FILLED && os!=ORDER_STATE_CANCELED && os!=ORDER_STATE_REJECTED && os!=ORDER_STATE_EXPIRED)
      { terminal=false; continue; }
      double expected=0;
      if(os!=ORDER_STATE_REJECTED)
      {
         expected=HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL);
         if(os!=ORDER_STATE_FILLED) expected-=HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT);
      }
      if(!HistorySelect(idea_start,TimeCurrent())) return false;
      double volume=0;
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         if((ulong)HistoryDealGetInteger(deal,DEAL_ORDER)!=order) continue;
         if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagicNumber ||
            HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol ||
            (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=g_half.position_id ||
            (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT)
         { BeginClose("Parcial con identidad o tipo inesperado"); return false; }
         volume+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      }
      if(MathAbs(expected-volume)>volume_step*0.1) return false;
      closed+=volume;
   }
   if(g_half.pending && (g_half.order==0 || !terminal)) return false;
   ulong ticket=HalfPosition();
   if(manual_required || !history_ok) return false;
   if(ticket!=0 && !PositionSelectByTicket(ticket)) return false;
   double remaining=ticket==0 ? 0 : PositionGetDouble(POSITION_VOLUME);
   if(closed>g_half.close_volume+volume_step*0.1)
   { BeginClose("Parcial excedio el volumen previsto"); return false; }
   if(!HistorySelect(idea_start,TimeCurrent())) return false;
   double all_exits=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if((ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=g_half.position_id) continue;
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) all_exits+=HistoryDealGetDouble(deal,DEAL_VOLUME);
   }
   // Include any concurrent SL/full close in the volume equation; otherwise
   // a completed partial could remain locked forever after that other exit.
   if(ticket!=0 && MathAbs(g_half.initial_volume-all_exits-remaining)>volume_step*0.1) return false;
   g_half.pending=false;
   // Full closure by SL/weekend/etc. is completed by the common close path.
   if(ticket==0 || state!=ACTIVE_IDEA || !g_half.triggered || g_half.trailing) return true;
   if(MathAbs(closed-g_half.close_volume)<=volume_step*0.1)
   {
      MqlTick q; if(!SymbolInfoTick(_Symbol,q)) { Problem("Parcial reconciliado sin cotizacion; esperar para iniciar trailing"); return false; }
      g_half.extreme=direction>0 ? q.bid : q.ask;
      g_half.trailing=true;
      Log("PARTIAL_CONFIRMED",StringFormat("cerrado=%.8f restante=%.8f trailing_inicio=%.10f ATR_congelado=%.10f",closed,remaining,g_half.extreme,frozen_atr),true);
   }
   return true;
}
void ObserveHalfExtreme()
{
   if(!HalfExitMode() || state!=ACTIVE_IDEA || !g_half.trailing) return;
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   if(direction>0) g_half.extreme=MathMax(g_half.extreme,q.bid);
   else g_half.extreme=MathMin(g_half.extreme,q.ask);
}
void HalfExitStep()
{
   if(!HalfExitMode() || state!=ACTIVE_IDEA || g_half.position_id==0) return;
   ObserveHalfExtreme();
   CheckOwnership(); if(manual_required || !history_ok) return;
   double closed=0;
   if(!ReconcileHalfExit(closed)) return;
   ulong ticket=HalfPosition();
   if(ticket==0 || manual_required || !history_ok || !PositionSelectByTicket(ticket)) return;
   if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=(direction>0 ? POSITION_TYPE_BUY : POSITION_TYPE_SELL))
   { BeginClose("Direccion inesperada durante salida parcial"); return; }
   double current_sl=PositionGetDouble(POSITION_SL);
   if(g_half.requested_sl>0 && SamePrice(current_sl,g_half.requested_sl))
   {
      if(direction>0 ? current_sl>g_sl : current_sl<g_sl)
      {
         Log("TRAIL_UPDATE",StringFormat("anterior=%.10f nuevo=%.10f extremo=%.10f ATR_congelado=%.10f",g_sl,current_sl,g_half.extreme,frozen_atr),true);
         g_sl=current_sl;
      }
      g_half.requested_sl=0;
   }
   if(!SamePrice(current_sl,g_sl)) { BeginClose("SL ausente o alterado durante salida parcial"); return; }
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   if(direction>0 ? q.bid<=g_sl : q.ask>=g_sl)
   { BeginClose("SL vigente alcanzado durante salida parcial"); return; }
   double candidate=g_sl;
   if(g_half.trailing)
   {
      if(direction>0) g_half.extreme=MathMax(g_half.extreme,q.bid);
      else g_half.extreme=MathMin(g_half.extreme,q.ask);
      double proposed=Price(g_half.extreme-direction*frozen_atr);
      bool tighter=direction>0 ? proposed>g_sl : proposed<g_sl;
      double distance=StopDistance();
      bool valid=direction>0 ? proposed<q.bid && q.bid-proposed>=distance : proposed>q.ask && proposed-q.ask>=distance;
      if(tighter && valid) candidate=proposed;
   }
   // Always remove any broker TP; SMA is a logical partial trigger only.
   bool remove_tp=!SamePrice(PositionGetDouble(POSITION_TP),0);
   if(remove_tp || !SamePrice(candidate,g_sl))
   {
      if(Locked(ticket,false) || !ManagementRequestAllowed(ticket,false)) return;
      g_half.requested_sl=candidate;
      trade.PositionModify(ticket,candidate,0);
      uint code=trade.ResultRetcode(); RememberManagementResult(ticket,false,code);
      if(Uncertain(code)) LockResult(ticket,false,false);
      if(code!=TRADE_RETCODE_DONE && code!=TRADE_RETCODE_NO_CHANGES) Problem("Trailing/TP pendiente; conservar SL vigente: "+trade.ResultRetcodeDescription());
      if(PositionSelectByTicket(ticket) && SamePrice(PositionGetDouble(POSITION_SL),candidate))
      {
         if(!SamePrice(candidate,g_sl)) Log("TRAIL_UPDATE",StringFormat("anterior=%.10f nuevo=%.10f extremo=%.10f ATR_congelado=%.10f",g_sl,candidate,g_half.extreme,frozen_atr),true);
         g_sl=candidate; g_half.requested_sl=0;
      }
      return;
   }
   if(g_half.trailing || g_half.pending) return;
   if(!g_half.triggered)
   {
      if(!HitTarget(q)) return;
      g_half.triggered=true;
      Log("PARTIAL_TARGET",StringFormat("objetivo=%.10f Bid=%.10f Ask=%.10f volumen_inicial=%.8f",target,q.bid,q.ask,g_half.initial_volume),true);
      if(!HalfSplit(g_half.initial_volume,g_half.close_volume))
      { Log("PARTIAL_NOT_POSSIBLE","division de volumen invalida; cerrar toda la idea",true); BeginClose("PARTIAL_NOT_POSSIBLE"); return; }
   }
   double amount=NormalizeDouble(g_half.close_volume-closed,8);
   if(!HalfVolumeValid(amount))
   { Log("PARTIAL_NOT_POSSIBLE","remanente de ejecucion parcial no negociable; cerrar toda la idea",true); BeginClose("PARTIAL_NOT_POSSIBLE"); return; }
   if(Locked(ticket,false) || !ManagementRequestAllowed(ticket,false)) return;
   // Recheck identity and exact volume immediately before sending a targeted
   // opposite deal. position is supplied for BOTH hedging and netting accounts.
   if(PositionOwner(ticket)!=1 || !PositionSelectByTicket(ticket) || manual_required || !history_ok) return;
   if(MathAbs(PositionGetDouble(POSITION_VOLUME)-(g_half.initial_volume-closed))>volume_step*0.1) return;
   MqlTradeRequest request={}; MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL; request.position=ticket; request.symbol=_Symbol; request.magic=InpMagicNumber;
   request.type=direction>0 ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.volume=amount; request.price=direction>0 ? q.bid : q.ask; request.deviation=InpDeviationPoints;
   long filling=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   request.type_filling=(filling & SYMBOL_FILLING_FOK)!=0 ? ORDER_FILLING_FOK : ((filling & SYMBOL_FILLING_IOC)!=0 ? ORDER_FILLING_IOC : ORDER_FILLING_RETURN);
   g_half.sequence++;
   g_half.comment=StringFormat("MRH.%I64d.%u",(long)idea_start,g_half.sequence); request.comment=g_half.comment;
   g_half.ticket=ticket; g_half.order=0; g_half.request_id=0; g_half.pending=true;
   Log("PARTIAL_REQUEST",StringFormat("ticket=%I64u volumen=%.8f restante_previsto=%.8f comentario=%s",ticket,amount,g_half.initial_volume-g_half.close_volume,g_half.comment),true);
   bool sent=OrderSend(request,result);
   g_half.request_id=result.request_id; g_half.order=result.order; HalfRememberOrder(result.order);
   RememberManagementResult(ticket,false,result.retcode);
   if(!sent && result.retcode==0)
   { Problem("Resultado de envio parcial desconocido; esperar historial, no duplicar"); }
   else HalfExitTransaction(request,result);
   if(g_half.pending) Log("PARTIAL_PENDING",StringFormat("request=%u orden=%I64u code=%u; esperar historial y volumen; no duplicar",result.request_id,result.order,result.retcode),true);
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
   ClearReentry("inicio de enfriamiento");
   cooldown_until=BarOf(closed)+600;
   state=COOLDOWN;
   if(HalfExitMode()) ResetHalfExit();
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
   if(!manual_required && history_ok && OwnPositions()==0 && OwnOrders()==0 && ArraySize(pending)==0 && !(HalfExitMode() && g_half.pending))
   {
      InspectIdeaHistory();
      if(manual_required || !history_ok) return;
      ObserveIdeaExcursions();
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
bool TargetInputs(const int shift,double &mid,double &upper,double &lower)
{
   if(InpStrategy!=ATR_DEVIATION_REENTRY) return Bands(shift,mid,upper,lower);
   upper=0; lower=0;
   return Value(sma_handle,0,shift,mid) && mid>0;
}
double Target(const double mid,const double upper,const double lower)
{
   if(InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_OPPOSITE_BAND_DYNAMIC)
      return Price(direction>0 ? upper : lower);
   if(InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_HALF_SMA20_DYNAMIC)
      return Price(entry_price+0.50*(mid-entry_price));
   if(InpStrategy!=ORIGINAL) return Price(mid);
   return Price(direction>0 ? lower+InpTPFactor*(mid-lower) : upper-InpTPFactor*(upper-mid));
}
bool Risk(const double volume,const double e1,const double e2,const double stop,double &risk)
{
   if(InpStrategy!=ORIGINAL)
   {
      if(volume<=0 || e1<=0 || stop<=0 || (direction>0 ? stop>=e1 : stop<=e1)) return false;
      double pnl=0;
      ENUM_ORDER_TYPE type=direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!OrderCalcProfit(type,_Symbol,volume,e1,stop,pnl)) return false;
      risk=-pnl; return MathIsValidNumber(risk) && risk>0;
   }
   if(volume<=0 || stop<=0 || e2<=0 || (direction>0 ? !(stop<e2 && e2<e1) : !(stop>e2 && e2>e1))) return false;
   double a=0,b=0;
   ENUM_ORDER_TYPE type=direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,_Symbol,volume,e1,stop,a) || !OrderCalcProfit(type,_Symbol,volume,e2,stop,b)) return false;
   risk=-(a+b); return MathIsValidNumber(risk) && risk>0;
}
void Levels(const double e1,double &e2,double &stop)
{
   e2=InpStrategy!=ORIGINAL ? 0 : Price(e1-direction*frozen_atr);
   stop=Price(e1-direction*(InpStrategy!=ORIGINAL ? InpReentrySLATR : 3.0)*frozen_atr);
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
   if(HalfExitMode()) { HalfExitStep(); return; }
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
      if(code==TRADE_RETCODE_DONE) Log(InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_ATR_FIXED_2 ? "TP_SYNC" : "TP_UPDATE",StringFormat("posicion=%I64u objetivo=%.5f TP_servidor=%.5f resultado=%u",t,target,broker_tp,code));
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
   double tp=(!HalfExitMode() && !HitTarget(q) && ValidTP(q)) ? target : 0;
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
   if(low<=lower && k<(InpOscillator==RSI ? InpRSIBuyLevel : 10) && processed_buy!=bar) return 1;
   if(high>=upper && k>(InpOscillator==RSI ? InpRSISellLevel : 90) && processed_sell!=bar) return -1;
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
string OscillatorSnapshot(const double value,const int shift)
{
   return StringFormat("oscilador=%s %s=%.10f shift=%d umbral_compra=%.10f umbral_venta=%.10f",
          InpOscillator==RSI ? "RSI" : "STOCHASTIC",InpOscillator==RSI ? "RSI" : "K",value,shift,
          InpOscillator==RSI ? InpRSIBuyLevel : 10.0,InpOscillator==RSI ? InpRSISellLevel : 90.0);
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
          "Open=%.5f High=%.5f Low=%.5f Close=%.5f LowerBand=%.10f SMA20=%.10f UpperBand=%.10f %s ATR=%.10f cierre_dentro_bandas=%s %s",
          TimeToString(evaluated,TIME_DATE|TIME_SECONDS),TimeToString(candle.time,TIME_DATE|TIME_SECONDS),
          TimeToString(nominal_close,TIME_DATE|TIME_SECONDS),elapsed,side>0 ? "BUY" : "SELL",
          candle.open,candle.high,candle.low,candle.close,lower,mid,upper,OscillatorSnapshot(k,1),atr_value,inside ? "true" : "false",market));
      return;
   }
   Log("SIGNAL",StringFormat("modo=%s vela=%s direccion=%s precio=%.5f low=%.5f high=%.5f BB=%.5f/%.5f/%.5f %s ATR=%.5f",
       InpSignalMode==INTRABAR ? "INTRABAR" : "CLOSED_BAR",TimeToString(candle.time,TIME_DATE|TIME_SECONDS),
       side>0 ? "BUY" : "SELL",candle.close,candle.low,candle.high,lower,mid,upper,OscillatorSnapshot(k,0),atr_value));
}
void EvaluateClosedBarSignal()
{
   MqlRates candle[1];
   double mid,upper,lower,k,atr_value;
   if(iTime(_Symbol,PERIOD_M5,0)!=g_last_signal_bar || CopyRates(_Symbol,PERIOD_M5,1,1,candle)!=1 ||
      candle[0].time>=g_last_signal_bar || !Bands(1,mid,upper,lower) || !Value(oscillator_handle,0,1,k) ||
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
bool ValidBBWInputs(const double mid,const double upper,const double lower)
{
   return MathIsValidNumber(mid) && MathIsValidNumber(upper) && MathIsValidNumber(lower) &&
          mid!=EMPTY_VALUE && upper!=EMPTY_VALUE && lower!=EMPTY_VALUE && mid>0 && upper>=lower;
}
bool ConfirmReentryBBWP70(const int side,const datetime candle,const double mid1,const double upper1,const double lower1)
{
   double reference[100],sorted[100];
   datetime newest=0,oldest=0,previous=candle;
   string reason="";
   int count=0;
   bool valid=ValidBBWInputs(mid1,upper1,lower1);
   double bbw1=0;
   if(valid) { bbw1=(upper1-lower1)/mid1; valid=MathIsValidNumber(bbw1); }
   if(!valid) reason="BBW1_invalido";
   if(valid)
   {
      for(int shift=2;shift<=101;shift++)
      {
         double mid,upper,lower;
         datetime bar=iTime(_Symbol,PERIOD_M5,shift);
         if(bar==0 || bar>=previous || !Bands(shift,mid,upper,lower))
         { reason=StringFormat("datos_referencia_no_disponibles_shift_%d",shift); valid=false; break; }
         if(!ValidBBWInputs(mid,upper,lower))
         { reason=StringFormat("datos_referencia_invalidos_shift_%d",shift); valid=false; break; }
         double value=(upper-lower)/mid;
         if(!MathIsValidNumber(value))
         { reason=StringFormat("BBW_no_finito_shift_%d",shift); valid=false; break; }
         reference[count]=value;
         if(count==0) newest=bar;
         oldest=bar; previous=bar; count++;
      }
   }
   if(!valid)
   {
      Log("BBW_FILTER",StringFormat("modo=BBW_BELOW_P70 direccion=%s vela1=%s BBW1=%s referencia_inicio=%s referencia_fin=%s valores=%d requeridos=100 P70=n/a resultado=DESCARTADA motivo=%s",
          side>0 ? "BUY" : "SELL",TimeToString(candle,TIME_DATE|TIME_SECONDS),
          reason=="BBW1_invalido" ? "n/a" : StringFormat("%.17g",bbw1),
          oldest==0 ? "n/a" : TimeToString(oldest,TIME_DATE|TIME_SECONDS),
          newest==0 ? "n/a" : TimeToString(newest,TIME_DATE|TIME_SECONDS),count,reason),true);
      return false;
   }
   // Sort a copy of exactly BBW[2..101], never including the signal candle.
   for(int i=0;i<100;i++) sorted[i]=reference[i];
   for(int i=1;i<100;i++)
   {
      double item=sorted[i]; int j=i-1;
      while(j>=0 && sorted[j]>item) { sorted[j+1]=sorted[j]; j--; }
      sorted[j+1]=item;
   }
   double p70=sorted[69]; // nearest rank 70 of 100; no interpolation or rounding.
   bool allowed=bbw1<p70;
   Log("BBW_FILTER",StringFormat("modo=BBW_BELOW_P70 direccion=%s vela1=%s BBW1=%.17g referencia_inicio=%s referencia_fin=%s valores=100 P70=%.17g resultado=%s motivo=%s",
       side>0 ? "BUY" : "SELL",TimeToString(candle,TIME_DATE|TIME_SECONDS),bbw1,
       TimeToString(oldest,TIME_DATE|TIME_SECONDS),TimeToString(newest,TIME_DATE|TIME_SECONDS),p70,
       allowed ? "PERMITIDA" : "DESCARTADA",allowed ? "BBW1_menor_P70" : "BBW1_no_menor_P70"),true);
   return allowed;
}
bool ConfirmReentryBBW(const int side,const datetime candle,const double mid1,const double upper1,const double lower1)
{
   if(InpStrategy!=BB_REENTRY || !InpReentryBBWFilter) return true;
   if(InpReentryBBWMode==BBW_BELOW_P70) return ConfirmReentryBBWP70(side,candle,mid1,upper1,lower1);
   double mid2=0,upper2=0,lower2=0;
   datetime previous=iTime(_Symbol,PERIOD_M5,2);
   string first=StringFormat("vela1=%s Upper1=%.17g Lower1=%.17g SMA1=%.17g",
       TimeToString(candle,TIME_DATE|TIME_SECONDS),upper1,lower1,mid1);
   if(previous==0 || previous>=candle || !Bands(2,mid2,upper2,lower2))
   {
      Log("BBW_FILTER",StringFormat("direccion=%s %s vela2=%s Upper2=n/a Lower2=n/a SMA2=n/a BBW1=n/a BBW2=n/a resultado=DESCARTADA motivo=datos_vela2_no_disponibles",
          side>0 ? "BUY" : "SELL",first,previous==0 ? "n/a" : TimeToString(previous,TIME_DATE|TIME_SECONDS)),true);
      return false;
   }
   string snapshot=first+StringFormat(" vela2=%s Upper2=%.17g Lower2=%.17g SMA2=%.17g",
       TimeToString(previous,TIME_DATE|TIME_SECONDS),upper2,lower2,mid2);
   if(!ValidBBWInputs(mid1,upper1,lower1) || !ValidBBWInputs(mid2,upper2,lower2))
   {
      Log("BBW_FILTER",StringFormat("direccion=%s %s BBW1=n/a BBW2=n/a resultado=DESCARTADA motivo=datos_invalidos_SMA_no_positiva_o_bandas_invertidas",
          side>0 ? "BUY" : "SELL",snapshot),true);
      return false;
   }
   double bbw1=(upper1-lower1)/mid1,bbw2=(upper2-lower2)/mid2;
   bool finite=MathIsValidNumber(bbw1) && MathIsValidNumber(bbw2);
   bool allowed=finite && bbw1<=bbw2; // Compare unrounded values; equality is allowed.
   Log("BBW_FILTER",StringFormat("direccion=%s %s BBW1=%.17g BBW2=%.17g resultado=%s motivo=%s",
       side>0 ? "BUY" : "SELL",snapshot,bbw1,bbw2,allowed ? "PERMITIDA" : "DESCARTADA",
       !finite ? "BBW_no_finito" : (allowed ? "ancho_no_aumenta" : "ancho_aumenta")),true);
   return allowed;
}
string ReentryADXModeName()
{
   if(InpReentryADXMode==ADX_BELOW_25) return "ADX_BELOW_25";
   if(InpReentryADXMode==ADX_BELOW_20) return "ADX_BELOW_20";
   if(InpReentryADXMode==ADX_BELOW_25_FALLING) return "ADX_BELOW_25_FALLING";
   return "ADX_OFF";
}
bool ConfirmReentryADX(const int side,const datetime candle)
{
   if(InpStrategy!=BB_REENTRY || InpReentryADXMode==ADX_OFF) return true;
   double adx1=0,adx2=0;
   string snapshot="ADX1=n/a";
   bool falling=InpReentryADXMode==ADX_BELOW_25_FALLING;
   if(!Value(adx_handle,0,1,adx1))
   {
      Log("ADX_FILTER",StringFormat("direccion=%s vela_reingreso=%s modo=%s ADX1=n/a resultado=DESCARTADA motivo=datos_ADX1_no_disponibles",
          side>0 ? "BUY" : "SELL",TimeToString(candle,TIME_DATE|TIME_SECONDS),ReentryADXModeName()),true);
      return false;
   }
   snapshot=StringFormat("ADX1=%.10f",adx1);
   if(falling)
   {
      if(!Value(adx_handle,0,2,adx2))
      {
         Log("ADX_FILTER",StringFormat("direccion=%s vela_reingreso=%s modo=%s %s ADX2=n/a resultado=DESCARTADA motivo=datos_ADX2_no_disponibles",
             side>0 ? "BUY" : "SELL",TimeToString(candle,TIME_DATE|TIME_SECONDS),ReentryADXModeName(),snapshot),true);
         return false;
      }
      snapshot+=StringFormat(" ADX2=%.10f",adx2);
   }
   double limit=InpReentryADXMode==ADX_BELOW_20 ? 20.0 : 25.0;
   bool allowed=adx1<limit;
   string reason=allowed ? "umbral_cumplido" : "umbral_no_cumplido";
   if(falling && allowed) { allowed=adx1<adx2; reason=allowed ? "umbral_y_descenso" : "sin_descenso_estricto"; }
   Log("ADX_FILTER",StringFormat("direccion=%s vela_reingreso=%s modo=%s %s resultado=%s motivo=%s",
       side>0 ? "BUY" : "SELL",TimeToString(candle,TIME_DATE|TIME_SECONDS),ReentryADXModeName(),snapshot,
       allowed ? "PERMITIDA" : "DESCARTADA",reason),true);
   return allowed;
}
bool ConfirmReentryMACD(const int side,const datetime exterior,const datetime candle)
{
   if(InpStrategy!=BB_REENTRY || !InpReentryMACDConfirm) return true;
   double main1,signal1,main2,signal2;
   if(!Value(macd_handle,0,1,main1) || !Value(macd_handle,1,1,signal1) ||
      !Value(macd_handle,0,2,main2) || !Value(macd_handle,1,2,signal2))
   {
      Log("MACD_CONFIRM",StringFormat("direccion=%s vela_exterior=%s vela_reingreso=%s MAIN1=n/a SIGNAL1=n/a H1=n/a H2=n/a resultado=DESCARTADA datos_MACD=no_disponibles; sin reintento tardio",
          side>0 ? "BUY" : "SELL",TimeToString(exterior,TIME_DATE|TIME_SECONDS),TimeToString(candle,TIME_DATE|TIME_SECONDS)),true);
      return false;
   }
   // MT5 draws MAIN_LINE as bars; H here is explicitly MAIN minus SIGNAL.
   double h1=main1-signal1,h2=main2-signal2;
   bool confirmed=MathIsValidNumber(h1) && MathIsValidNumber(h2) &&
       (side>0 ? h1<0 && h1>h2 : h1>0 && h1<h2);
   Log("MACD_CONFIRM",StringFormat("direccion=%s vela_exterior=%s vela_reingreso=%s MAIN1=%.10f SIGNAL1=%.10f H1=%.10f H2=%.10f resultado=%s",
       side>0 ? "BUY" : "SELL",TimeToString(exterior,TIME_DATE|TIME_SECONDS),TimeToString(candle,TIME_DATE|TIME_SECONDS),
       main1,signal1,h1,h2,confirmed ? "CONFIRMADA" : "DESCARTADA"),true);
   return confirmed;
}
void EvaluateReentrySignal()
{
   MqlRates candle[1];
   double mid,upper,lower,atr_value;
   if(iTime(_Symbol,PERIOD_M5,0)!=g_last_signal_bar || CopyRates(_Symbol,PERIOD_M5,1,1,candle)!=1)
   {
      Log("REJECTED","estrategia=BB_REENTRY serie M5 no disponible; oportunidad descartada",true);
      ClearReentry("datos de velas no disponibles");
      return;
   }
   if(candle[0].time+PeriodSeconds(PERIOD_M5)!=g_last_signal_bar)
   {
      Log("REJECTED",StringFormat("estrategia=BB_REENTRY vela=%s nueva_vela=%s sin continuidad; oportunidad descartada",
          TimeToString(candle[0].time,TIME_DATE|TIME_SECONDS),TimeToString(g_last_signal_bar,TIME_DATE|TIME_SECONDS)),true);
      ClearReentry("pausa de sesion o datos");
      return;
   }
   if(!Bands(1,mid,upper,lower) || !Value(atr_handle,0,1,atr_value))
   {
      Log("REJECTED","estrategia=BB_REENTRY indicadores no disponibles; oportunidad descartada",true);
      ClearReentry("indicadores no disponibles");
      return;
   }
   if(InpReentryBBWFilter && !ValidBBWInputs(mid,upper,lower))
   {
      Log("REJECTED","BBW datos vela1 invalidos; preparacion descartada",true);
      ClearReentry("datos Bollinger invalidos para BBW");
      return;
   }
   ReentryState outside=NONE;
   if(candle[0].close<lower) outside=WAIT_BUY_REENTRY;
   else if(candle[0].close>upper) outside=WAIT_SELL_REENTRY;
   if(outside!=NONE)
   {
      if(outside!=reentry_state)
      {
         ClearReentry("sustitucion por cierre exterior opuesto");
         reentry_state=outside;
         reentry_outer_bar=candle[0].time;
         Log("PREPARATION",StringFormat("estrategia=BB_REENTRY direccion=%s vela=%s Close=%.10f LowerBand=%.10f UpperBand=%.10f",
             outside==WAIT_BUY_REENTRY ? "BUY" : "SELL",TimeToString(candle[0].time,TIME_DATE|TIME_SECONDS),candle[0].close,lower,upper));
      }
      return;
   }
   if(reentry_state==NONE || candle[0].time<=reentry_outer_bar || candle[0].close<=lower || candle[0].close>=upper) return;
   int side=reentry_state==WAIT_BUY_REENTRY ? 1 : -1;
   datetime exterior=reentry_outer_bar;
   ClearReentry(InpReentryMACDConfirm ? "primer cierre interior; preparacion consumida" : "reingreso confirmado; preparacion consumida");
   bool macd_ok=ConfirmReentryMACD(side,exterior,candle[0].time);
   bool adx_ok=ConfirmReentryADX(side,candle[0].time);
   bool bbw_ok=ConfirmReentryBBW(side,candle[0].time,mid,upper,lower);
   if(!macd_ok || !adx_ok || !bbw_ok) return;
   if((side>0 && processed_buy==candle[0].time) || (side<0 && processed_sell==candle[0].time)) return;
   if(side>0) processed_buy=candle[0].time;
   else processed_sell=candle[0].time;
   if(!SaveSignal()) return;
   Log("SIGNAL",StringFormat("estrategia=BB_REENTRY modo=CLOSED_BAR direccion=%s vela_exterior=%s vela=%s Close=%.10f LowerBand=%.10f UpperBand=%.10f SMA20=%.10f ATR=%.10f shift=1",
       side>0 ? "BUY" : "SELL",TimeToString(exterior,TIME_DATE|TIME_SECONDS),TimeToString(candle[0].time,TIME_DATE|TIME_SECONDS),
       candle[0].close,lower,upper,mid,atr_value));
   OpenIdea(side,atr_value,mid,upper,lower);
   TrackCurrent();
   if(state==CLOSING_IDEA) CloseStep();
}
void EvaluateATRDeviationSignal()
{
   MqlRates candle[1]; double sma,atr_value;
   if(iTime(_Symbol,PERIOD_M5,0)!=g_last_signal_bar || CopyRates(_Symbol,PERIOD_M5,1,1,candle)!=1 ||
      !Value(sma_handle,0,1,sma) || !Value(atr_handle,0,1,atr_value))
   { Log("REJECTED","estrategia=ATR_DEVIATION_REENTRY datos no disponibles; oportunidad descartada",true); ClearReentry("datos no disponibles"); return; }
   if(candle[0].time+PeriodSeconds(PERIOD_M5)!=g_last_signal_bar)
   { Log("REJECTED","estrategia=ATR_DEVIATION_REENTRY discontinuidad; oportunidad descartada",true); ClearReentry("discontinuidad de barras"); return; }
   if(!MathIsValidNumber(candle[0].close) || candle[0].close==EMPTY_VALUE || candle[0].close<=0 ||
      !MathIsValidNumber(sma) || sma==EMPTY_VALUE || sma<=0 || !MathIsValidNumber(atr_value) || atr_value==EMPTY_VALUE || atr_value<=0)
   { Log("REJECTED","estrategia=ATR_DEVIATION_REENTRY Close/SMA/ATR invalidos",true); ClearReentry("datos invalidos"); return; }
   double d=(candle[0].close-sma)/atr_value,t=InpATRDeviationThreshold;
   if(!MathIsValidNumber(d)) { Log("REJECTED","estrategia=ATR_DEVIATION_REENTRY D no finito",true); ClearReentry("D invalido"); return; }
   ReentryState outside=NONE;
   if(d<-t) outside=WAIT_BUY_REENTRY;
   else if(d>t) outside=WAIT_SELL_REENTRY;
   if(outside!=NONE)
   {
      if(outside!=reentry_state)
      {
         ClearReentry("sustitucion por extremo opuesto");
         reentry_state=outside; reentry_outer_bar=candle[0].time;
         deviation_prep_close=candle[0].close; deviation_prep_sma=sma; deviation_prep_atr=atr_value; deviation_prep_d=d;
         Log("PREPARATION",StringFormat("estrategia=ATR_DEVIATION_REENTRY direccion=%s vela=%s Close=%.17g SMA20=%.17g ATR14=%.17g D=%.17g",
             outside==WAIT_BUY_REENTRY ? "BUY" : "SELL",TimeToString(candle[0].time,TIME_DATE|TIME_SECONDS),candle[0].close,sma,atr_value,d));
      }
      return;
   }
   if((reentry_state==WAIT_BUY_REENTRY && d>=0) || (reentry_state==WAIT_SELL_REENTRY && d<=0))
   { ClearReentry("media alcanzada o cruzada sin confirmacion"); return; }
   bool buy=reentry_state==WAIT_BUY_REENTRY && -t<d && d<0;
   bool sell=reentry_state==WAIT_SELL_REENTRY && 0<d && d<t;
   if((!buy && !sell) || candle[0].time<=reentry_outer_bar) return;
   int side=buy ? 1 : -1;
   datetime prepared=reentry_outer_bar;
   double pc=deviation_prep_close,ps=deviation_prep_sma,pa=deviation_prep_atr,pd=deviation_prep_d;
   ClearReentry("confirmacion consumida");
   if((side>0 && processed_buy==candle[0].time) || (side<0 && processed_sell==candle[0].time)) return;
   if(side>0) processed_buy=candle[0].time; else processed_sell=candle[0].time;
   if(!SaveSignal()) return;
   MqlTick quote={}; string market="mercado_disponible=false";
   if(SymbolInfoTick(_Symbol,quote)) market=StringFormat("mercado_disponible=true mercado_bid=%.10f mercado_ask=%.10f mercado_referencia_e1=%.10f",quote.bid,quote.ask,side>0 ? quote.ask : quote.bid);
   Log("SIGNAL",StringFormat("estrategia=ATR_DEVIATION_REENTRY evaluacion=%s direccion=%s preparacion=%s confirmacion=%s shift=1 Close_preparacion=%.17g SMA_preparacion=%.17g ATR_preparacion=%.17g D_preparacion=%.17g Close_confirmacion=%.17g SMA_confirmacion=%.17g ATR_confirmacion=%.17g D_confirmacion=%.17g cambio_Close=%.17g cambio_SMA=%.17g cambio_ATR=%.17g %s",
       TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),side>0 ? "BUY" : "SELL",TimeToString(prepared,TIME_DATE|TIME_SECONDS),TimeToString(candle[0].time,TIME_DATE|TIME_SECONDS),
       pc,ps,pa,pd,candle[0].close,sma,atr_value,d,candle[0].close-pc,sma-ps,atr_value-pa,market));
   OpenIdea(side,atr_value,sma,0,0);
   TrackCurrent(); if(state==CLOSING_IDEA) CloseStep();
}
int WickSignalSide(const MqlRates &candle,const double mid,const double upper,const double lower)
{
   if(!ValidBBWInputs(mid,upper,lower) || !MathIsValidNumber(candle.open) || !MathIsValidNumber(candle.close) ||
      !MathIsValidNumber(candle.high) || !MathIsValidNumber(candle.low) || candle.open==EMPTY_VALUE ||
      candle.close==EMPTY_VALUE || candle.high==EMPTY_VALUE || candle.low==EMPTY_VALUE || candle.low<=0 ||
      candle.high<=candle.low || candle.open<candle.low || candle.open>candle.high ||
      candle.close<candle.low || candle.close>candle.high) return -2;
   double range=candle.high-candle.low;
   if(!MathIsValidNumber(range)) return -2;
   if(candle.close<=lower || candle.close>=upper) return 0;
   bool buy=candle.low<=lower && (MathMin(candle.open,candle.close)-candle.low)/range>=InpWickMinRatio;
   bool sell=candle.high>=upper && (candle.high-MathMax(candle.open,candle.close))/range>=InpWickMinRatio;
   if(buy && sell) return 2;
   return buy ? 1 : (sell ? -1 : 0);
}
void EvaluateWickSignal()
{
   MqlRates candle[1]; double mid,upper,lower,atr_value;
   if(iTime(_Symbol,PERIOD_M5,0)!=g_last_signal_bar || CopyRates(_Symbol,PERIOD_M5,1,1,candle)!=1 ||
      !Bands(1,mid,upper,lower) || !Value(atr_handle,0,1,atr_value))
   { Log("REJECTED","estrategia=BB_WICK_REJECTION datos no disponibles; oportunidad descartada",true); return; }
   if(candle[0].time+PeriodSeconds(PERIOD_M5)!=g_last_signal_bar)
   { Log("REJECTED","estrategia=BB_WICK_REJECTION vela antigua sin continuidad; oportunidad descartada",true); return; }
   int side=WickSignalSide(candle[0],mid,upper,lower);
   if(side==-2) { Log("REJECTED","estrategia=BB_WICK_REJECTION OHLC/Bollinger invalidos o rango no positivo",true); return; }
   if(side==2) { Log("AMBIGUOUS_SIGNAL","estrategia=BB_WICK_REJECTION vela="+TimeToString(candle[0].time,TIME_DATE|TIME_SECONDS)+" compra y venta; ambas descartadas",true); return; }
   if(side==0 || (side>0 && processed_buy==candle[0].time) || (side<0 && processed_sell==candle[0].time)) return;
   if(side>0) processed_buy=candle[0].time; else processed_sell=candle[0].time;
   if(!SaveSignal()) return;
   double range=candle[0].high-candle[0].low,body=MathAbs(candle[0].close-candle[0].open);
   double bottom=MathMin(candle[0].open,candle[0].close)-candle[0].low;
   double top=candle[0].high-MathMax(candle[0].open,candle[0].close);
   string distance=atr_value>0 ? StringFormat("%.17g",(side>0 ? candle[0].close-lower : upper-candle[0].close)/atr_value) : "n/a";
   MqlTick quote={}; string market="mercado_disponible=false";
   if(SymbolInfoTick(_Symbol,quote)) market=StringFormat("mercado_disponible=true mercado_bid=%.10f mercado_ask=%.10f mercado_referencia_e1=%.10f",quote.bid,quote.ask,side>0 ? quote.ask : quote.bid);
   Log("SIGNAL",StringFormat("estrategia=BB_WICK_REJECTION evaluacion=%s vela=%s direccion=%s shift=1 Open=%.10f High=%.10f Low=%.10f Close=%.10f LowerBand=%.10f SMA20=%.10f UpperBand=%.10f ATR=%.10f rango=%.17g cuerpo=%.17g mecha_inferior=%.17g mecha_superior=%.17g ratio_inferior=%.17g ratio_superior=%.17g cuerpo_rango=%.17g distancia_cierre_ATR=%s %s",
       TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),TimeToString(candle[0].time,TIME_DATE|TIME_SECONDS),side>0 ? "BUY" : "SELL",
       candle[0].open,candle[0].high,candle[0].low,candle[0].close,lower,mid,upper,atr_value,range,body,bottom,top,bottom/range,top/range,body/range,distance,market));
   OpenIdea(side,atr_value,mid,upper,lower);
   TrackCurrent(); if(state==CLOSING_IDEA) CloseStep();
}
bool ATRAllowed(const double value) { return value>0 && value<=(InpStrategy==BB_REENTRY ? 8.0 : InpATRMax); }
void OpenIdea(const int side,const double atr_value,const double mid,const double upper,const double lower)
{
   direction=side; frozen_atr=atr_value;
   if(!ATRAllowed(frozen_atr)) { Log("REJECTED","ATR fuera de rango"); return; }
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   if(!Size(side>0 ? q.ask : q.bid,lot)) { Log("REJECTED","Calculo de riesgo o lote insuficiente"); return; }
   CheckOwnership();
   if(manual_required || !history_ok || ForeignExposure() || OwnPositions()>0 || OwnOrders()>0) return;
   ClearReentry("inicio de idea");
   idea_start=TimeCurrent(); realized=0; entries=0; e1_order=0; e2_order=0; had_exposure=false;
   ArrayResize(position_ids,0);
   ResetExcursions();
   ResetHalfExit();
   target=(InpStrategy==BB_REENTRY && (InpReentryExitMode==EXIT_ATR_FIXED_2 || InpReentryExitMode==EXIT_HALF_SMA20_DYNAMIC || InpReentryExitMode==EXIT_OPPOSITE_BAND_DYNAMIC)) ? 0 : Target(mid,upper,lower); tp_bar=iTime(_Symbol,PERIOD_M5,0);
   state=ACTIVE_IDEA;
   // FOK when available; otherwise IOC, with partial execution handled by abort.
   long filling=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK)!=0) trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC)!=0) trade.SetTypeFilling(ORDER_FILLING_IOC);
   else trade.SetTypeFilling(ORDER_FILLING_RETURN);
   bool sent=side>0 ? trade.Buy(lot,_Symbol,0,0,0,"MR E1") : trade.Sell(lot,_Symbol,0,0,0,"MR E1");
   uint code=trade.ResultRetcode(); e1_order=trade.ResultOrder();
   ObserveIdeaExcursions();
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
      if(HalfExitMode()) g_half.position_id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   }
   if(executed>0) entry_price/=executed;
   if(entry_price<=0 || MathAbs(executed-lot)>volume_step*0.1)
   { Abort("E1 volumen parcial o precio desconocido"); return; }
   entries=1; had_exposure=true;
   if(HalfExitMode()) g_half.initial_volume=executed;
   double e2,risk;
   Levels(entry_price,e2,g_sl);
   if(!Risk(executed,entry_price,e2,g_sl,risk) || risk>Budget())
   { Abort("Riesgo real excedido o calculo fallido"); return; }
   if(InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_ATR_FIXED_2)
      target=Price(entry_price+direction*2.0*frozen_atr);
   else if(InpStrategy==BB_REENTRY && (InpReentryExitMode==EXIT_HALF_SMA20_DYNAMIC || InpReentryExitMode==EXIT_OPPOSITE_BAND_DYNAMIC))
      target=Target(mid,upper,lower);
   if(!SetInitialSL()) { Abort("No se pudo establecer SL valido"); return; }
   if(!SymbolInfoTick(_Symbol,q)) { Abort("Sin cotizacion despues de E1"); return; }
   if(InpStrategy==BB_REENTRY)
      Log("ENTRY",StringFormat("estrategia=BB_REENTRY salida=%s E1=%.5f E1_orden=%I64u ATR_congelado=%.10f lote=%.8f SL=%.5f TP=%.5f riesgo=%.2f SL_ATR=%.10f entradas=1",
          InpReentryExitMode==EXIT_ATR_FIXED_2 ? "EXIT_ATR_FIXED_2" : (InpReentryExitMode==EXIT_HALF_SMA20_DYNAMIC ? "EXIT_HALF_SMA20_DYNAMIC" : (InpReentryExitMode==EXIT_OPPOSITE_BAND_DYNAMIC ? "EXIT_OPPOSITE_BAND_DYNAMIC" : (InpReentryExitMode==EXIT_HALF_SMA20_TRAIL_ATR ? "EXIT_HALF_SMA20_TRAIL_ATR" : "EXIT_SMA20_DYNAMIC"))),entry_price,e1_order,frozen_atr,lot,g_sl,target,risk,InpReentrySLATR),true);
   else if(InpStrategy!=ORIGINAL)
      Log("ENTRY",StringFormat("estrategia=%s E1=%.5f E1_orden=%I64u lote=%.8f SL=%.5f TP=%.5f riesgo=%.2f SL_ATR=%.10f entradas=1",
          InpStrategy==BB_REENTRY ? "BB_REENTRY" : (InpStrategy==BB_WICK_REJECTION ? "BB_WICK_REJECTION" : "ATR_DEVIATION_REENTRY"),entry_price,e1_order,lot,g_sl,target,risk,InpReentrySLATR),true);
   if(HalfExitMode()) { HalfExitStep(); return; }
   if(HitTarget(q)) { BeginClose("TP inicial alcanzado"); return; }
   if(InpStrategy!=ORIGINAL) return; // E1 is the only entry; no pending order.
   if(direction>0 ? q.ask-e2<StopDistance() || e2>=q.ask : e2-q.bid<StopDistance() || e2<=q.bid)
   { Abort("E2 stops invalidos"); return; }
   double tp=ValidTP(q) ? target : 0;
   if(tp!=0 && (direction>0 ? tp-e2<StopDistance() : e2-tp<StopDistance())) tp=0;
   CheckOwnership(); if(manual_required || !history_ok) { Abort("Propiedad no verificable"); return; }
   // Pending orders use RETURN as prescribed by MT5, independently of market filling.
   trade.SetTypeFilling(ORDER_FILLING_RETURN);
   sent=direction>0 ? trade.BuyLimit(lot,e2,_Symbol,g_sl,tp,ORDER_TIME_GTC,0,"MR E2") : trade.SellLimit(lot,e2,_Symbol,g_sl,tp,ORDER_TIME_GTC,0,"MR E2");
   code=trade.ResultRetcode(); e2_order=trade.ResultOrder();
   ObserveIdeaExcursions();
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
         if(state==ACTIVE_IDEA && !IgnoreHalfDeal(d)) BeginClose("Cierre detectado en historial de la idea");
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
   g_exit_reports[n].excursions=g_excursions;
   g_exit_reports[n].first_execution_msc=0;
   g_exit_reports[n].last_exit_msc=0;
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
bool DiagnosticOrderVolume(ExitReport &report,const ulong order,const bool final_sample,double &executed)
{
   if(!final_sample && order!=0 && OrderSelect(order))
   {
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol || (ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) return false;
      executed=OrderGetDouble(ORDER_VOLUME_INITIAL)-OrderGetDouble(ORDER_VOLUME_CURRENT);
      if(executed<0) return false;
      if(executed>0) ReportAddId(report,(ulong)OrderGetInteger(ORDER_POSITION_ID));
      return true;
   }
   return ReportOrderVolume(report,order,executed);
}
bool ReconcileIdeaPnl(ExitReport &report,const bool final_sample,double &pnl,int &entry_count)
{
   pnl=0; entry_count=0;
   double expected_first=0,expected_second=0;
   if(!DiagnosticOrderVolume(report,report.first_order,final_sample,expected_first) ||
      !DiagnosticOrderVolume(report,report.second_order,final_sample,expected_second)) return false;
   // Normal ideas need only their lifetime; startup cleanup without an E1
   // order needs older history too. Include the whole current second, no cursor.
   datetime from=report.first_order!=0 ? report.idea_id : 0;
   if(!HistorySelect(from,TimeCurrent())) return false;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagicNumber) continue;
      ulong order=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
      if((report.first_order!=0 && order==report.first_order) || (report.second_order!=0 && order==report.second_order))
         ReportAddId(report,(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID));
   }
   DiagnosticPosition live[];
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(!ReportHasId(report,id))
      {
         // An entry whose history/identity has not arrived yet is not zero PnL.
         if(!final_sample && (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) return false;
         continue;
      }
      if(final_sample || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) return false;
      int n=ArraySize(live); ArrayResize(live,n+1);
      live[n].ticket=ticket; live[n].id=id;
      live[n].volume=PositionGetDouble(POSITION_VOLUME);
      live[n].profit=PositionGetDouble(POSITION_PROFIT);
      live[n].swap=PositionGetDouble(POSITION_SWAP);
      live[n].updated_msc=PositionGetInteger(POSITION_TIME_UPDATE_MSC);
   }
   long first_msc=0,last_exit_msc=0;
   long latest_deal_msc[];
   ArrayResize(latest_deal_msc,ArraySize(report.ids)); ArrayInitialize(latest_deal_msc,0);
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
      long stamp=HistoryDealGetInteger(d,DEAL_TIME_MSC);
      if(stamp<=0) return false;
      for(int j=0;j<ArraySize(report.ids);j++)
         if(report.ids[j]==id && stamp>latest_deal_msc[j]) latest_deal_msc[j]=stamp;
      if(entry==DEAL_ENTRY_IN)
      {
         if(first_msc==0 || stamp<first_msc) first_msc=stamp;
         if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)!=InpMagicNumber) return false;
         if(order==report.first_order) first_volume+=volume;
         if(order==report.second_order) second_volume+=volume;
         bool seen=false;
         for(int j=0;j<ArraySize(entry_orders);j++) if(entry_orders[j]==order) { seen=true; break; }
         if(!seen) { int n=ArraySize(entry_orders); ArrayResize(entry_orders,n+1); entry_orders[n]=order; }
      }
      if((entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) && stamp>last_exit_msc) last_exit_msc=stamp;
      pnl+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_SWAP)+
           HistoryDealGetDouble(d,DEAL_COMMISSION)+HistoryDealGetDouble(d,DEAL_FEE);
   }
   double tolerance=volume_step*0.1;
   if(MathAbs(first_volume-expected_first)>tolerance || MathAbs(second_volume-expected_second)>tolerance) return false;
   if(report.exposed && ArraySize(report.ids)==0) return false;
   for(int i=0;i<ArraySize(report.ids);i++)
   {
      double open_volume=0;
      for(int j=0;j<ArraySize(live);j++) if(live[j].id==report.ids[i]) open_volume+=live[j].volume;
      if(incoming[i]<=0 || MathAbs(incoming[i]-outgoing[i]-open_volume)>tolerance) return false;
   }
   // Re-read the portfolio after history: a partial/full close or E2 fill in
   // between must invalidate the sample, not duplicate realized + stale float.
   for(int j=0;j<ArraySize(live);j++)
   {
      // Offset fills/closes can leave netting volume unchanged. The latest
      // volume-update time must still be represented in the selected history.
      for(int k=0;k<ArraySize(report.ids);k++)
         if(report.ids[k]==live[j].id && live[j].updated_msc>latest_deal_msc[k]) return false;
      if(!PositionSelectByTicket(live[j].ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_IDENTIFIER)!=live[j].id ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber ||
         PositionGetInteger(POSITION_TIME_UPDATE_MSC)!=live[j].updated_msc ||
         MathAbs(PositionGetDouble(POSITION_VOLUME)-live[j].volume)>tolerance ||
         PositionGetDouble(POSITION_SWAP)!=live[j].swap || PositionGetDouble(POSITION_PROFIT)!=live[j].profit) return false;
      pnl+=live[j].profit+live[j].swap;
   }
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(!ReportHasId(report,id))
      {
         if(!final_sample && (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber) return false;
         continue;
      }
      bool found=false;
      for(int j=0;j<ArraySize(live);j++) if(live[j].ticket==ticket) { found=true; break; }
      if(!found) return false;
   }
   if(!MathIsValidNumber(pnl)) return false;
   report.first_execution_msc=first_msc;
   report.last_exit_msc=last_exit_msc;
   entry_count=ArraySize(entry_orders);
   return !report.exposed || entry_count>0;
}
bool ReconcileExitReport(ExitReport &report,double &pnl,int &entry_count)
{
   return ReconcileIdeaPnl(report,true,pnl,entry_count);
}
void ResetExcursions()
{
   g_excursions.e1_msc=0;
   g_excursions.mfe=0; g_excursions.mae=0;
   g_excursions.mfe_at=0; g_excursions.mae_at=0;
   g_excursions.risk_budget=Budget();
}
void UpdateExcursions(ExcursionStats &stats,const double pnl,const long first_msc,const datetime observed_at)
{
   if(first_msc<=0 || !MathIsValidNumber(pnl)) return;
   if(stats.e1_msc==0)
   {
      stats.e1_msc=first_msc;
      stats.mfe=0; stats.mae=0;
      stats.mfe_at=(datetime)(first_msc/1000); stats.mae_at=stats.mfe_at;
      if(stats.risk_budget<=0) stats.risk_budget=Budget();
   }
   if(pnl>stats.mfe) { stats.mfe=pnl; stats.mfe_at=observed_at; }
   if(pnl<stats.mae) { stats.mae=pnl; stats.mae_at=observed_at; }
}
void ObserveIdeaExcursions()
{
   if(idea_start==0 || (state!=ACTIVE_IDEA && state!=CLOSING_IDEA)) return;
   ExitReport sample;
   sample.idea_id=idea_start;
   sample.first_order=e1_order; sample.second_order=e2_order;
   sample.exposed=true;
   ArrayCopy(sample.ids,position_ids);
   double pnl=0; int count=0;
   // Deliberately independent of history_ok and all operational decisions.
   if(ReconcileIdeaPnl(sample,false,pnl,count))
      UpdateExcursions(g_excursions,pnl,sample.first_execution_msc,TimeCurrent());
}
string ExitDiagnosticText(const ExitReport &report)
{
   bool available=report.excursions.e1_msc>0;
   double risk=report.excursions.risk_budget;
   if(risk<=0) risk=Budget();
   double duration=available && report.last_exit_msc>=report.excursions.e1_msc ?
                   (double)(report.last_exit_msc-report.excursions.e1_msc)/1000.0 : 0;
   return StringFormat("MFE_MAE_disponible=%s MFE_USD=%.2f MAE_USD=%.2f MFE_fecha=%s MAE_fecha=%s riesgo_presupuestado_USD=%.2f MFE_R=%.6f MAE_R=%.6f duracion_segundos=%.3f",
          available ? "true" : "false",report.excursions.mfe,report.excursions.mae,
          available ? TimeToString(report.excursions.mfe_at,TIME_DATE|TIME_SECONDS) : "n/a",
          available ? TimeToString(report.excursions.mae_at,TIME_DATE|TIME_SECONDS) : "n/a",
          risk,risk>0 ? report.excursions.mfe/risk : 0,risk>0 ? report.excursions.mae/risk : 0,duration);
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
      g_exit_reports[j].excursions=g_exit_reports[j+1].excursions;
      g_exit_reports[j].first_execution_msc=g_exit_reports[j+1].first_execution_msc;
      g_exit_reports[j].last_exit_msc=g_exit_reports[j+1].last_exit_msc;
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
         // Final realized PnL is itself an observation, even if exit deals
         // arrived after cooldown or after the next idea started.
         UpdateExcursions(g_exit_reports[i].excursions,pnl,g_exit_reports[i].first_execution_msc,
                          (datetime)(g_exit_reports[i].last_exit_msc/1000));
         PrintFormat("EXIT %s idea=%I64d cierre=%s motivo=%s PnL_realizado=%.2f entradas=%d %s",
                     TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),(long)g_exit_reports[i].idea_id,
                     TimeToString(g_exit_reports[i].closed_at,TIME_DATE|TIME_SECONDS),g_exit_reports[i].reason,pnl,count,ExitDiagnosticText(g_exit_reports[i]));
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
   if((InpStrategy!=ORIGINAL && InpStrategy!=BB_REENTRY && InpStrategy!=BB_WICK_REJECTION && InpStrategy!=ATR_DEVIATION_REENTRY) || InpMagicNumber==0 ||
      !MathIsValidNumber(InpRiskBaseUSD) || InpRiskBaseUSD<=0 ||
      !MathIsValidNumber(InpRiskPercent) || InpRiskPercent<=0 || InpRiskPercent>100 ||
      (InpStrategy==BB_REENTRY && InpReentryExitMode!=EXIT_SMA20_DYNAMIC && InpReentryExitMode!=EXIT_ATR_FIXED_2 && InpReentryExitMode!=EXIT_HALF_SMA20_DYNAMIC && InpReentryExitMode!=EXIT_OPPOSITE_BAND_DYNAMIC && InpReentryExitMode!=EXIT_HALF_SMA20_TRAIL_ATR) ||
      (InpStrategy==BB_REENTRY && InpReentryBBWFilter && InpReentryBBWMode!=BBW_NON_INCREASING && InpReentryBBWMode!=BBW_BELOW_P70) ||
      (InpStrategy==BB_REENTRY && InpReentryADXMode!=ADX_OFF && InpReentryADXMode!=ADX_BELOW_25 &&
       InpReentryADXMode!=ADX_BELOW_20 && InpReentryADXMode!=ADX_BELOW_25_FALLING) ||
      (InpStrategy==BB_REENTRY && InpReentryMACDConfirm && (InpMACDFast<=0 || InpMACDSlow<=0 || InpMACDSignal<=0 || InpMACDFast>=InpMACDSlow)) ||
      (WeekendGuardEnabled() && (InpWeekendCloseMinutes<=0 || InpWeekendEntryBlockMinutes<InpWeekendCloseMinutes)) ||
      (InpStrategy==ATR_DEVIATION_REENTRY && (!MathIsValidNumber(InpATRDeviationThreshold) || InpATRDeviationThreshold<=0 || !MathIsValidNumber(InpATRMax) || InpATRMax<=0)) ||
      (InpStrategy==BB_WICK_REJECTION && (!MathIsValidNumber(InpWickMinRatio) || InpWickMinRatio<=0 || InpWickMinRatio>1 || !MathIsValidNumber(InpATRMax) || InpATRMax<=0)) ||
      (InpStrategy!=ORIGINAL && (!MathIsValidNumber(InpReentrySLATR) || InpReentrySLATR<=0)) ||
      (InpStrategy==ORIGINAL && (
       (InpSignalMode!=INTRABAR && InpSignalMode!=CLOSED_BAR) ||
       InpBollingerPeriod<2 || !MathIsValidNumber(InpBollingerDeviation) || InpBollingerDeviation<=0 ||
       (InpOscillator!=STOCHASTIC && InpOscillator!=RSI) ||
       (InpOscillator==STOCHASTIC && (InpStochasticK<1 || InpStochasticD<1 || InpStochasticSlowing<1)) ||
       (InpOscillator==RSI && (InpRSIPeriod<=0 || !MathIsValidNumber(InpRSIBuyLevel) ||
        !MathIsValidNumber(InpRSISellLevel) || InpRSIBuyLevel<=0 || InpRSIBuyLevel>=InpRSISellLevel || InpRSISellLevel>=100)) ||
       InpATRPeriod<1 || !MathIsValidNumber(InpATRMax) || InpATRMax<=0 ||
       !MathIsValidNumber(InpTPFactor) || InpTPFactor<=0 || InpTPFactor>1)))
   { Print("INIT_FAILED: parametros invalidos"); return INIT_PARAMETERS_INCORRECT; }
   tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   volume_min=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   volume_max=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   volume_step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(tick_size<=0 || volume_min<=0 || volume_step<=0 || volume_max<volume_min || !MathIsValidNumber(Budget()) || Budget()<=0)
      return INIT_FAILED;
   signal_key=SignalKey();
   if(InpStrategy==ATR_DEVIATION_REENTRY) signal_key+="ATRDEV.";
   else if(InpStrategy==BB_WICK_REJECTION) signal_key+="WICK.";
   else if(InpStrategy==BB_REENTRY) signal_key+="BB.";
   else
   {
      if(InpSignalMode==CLOSED_BAR) signal_key+="C.";
      if(InpOscillator==RSI) signal_key+="R.";
   }
   if(GlobalVariableCheck(signal_key+"B")) processed_buy=(datetime)GlobalVariableGet(signal_key+"B");
   if(GlobalVariableCheck(signal_key+"S")) processed_sell=(datetime)GlobalVariableGet(signal_key+"S");
   netting=(ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetMarginMode();
   if(InpStrategy==ATR_DEVIATION_REENTRY)
      sma_handle=iMA(_Symbol,PERIOD_M5,20,0,MODE_SMA,PRICE_CLOSE);
   else bands=iBands(_Symbol,PERIOD_M5,InpStrategy!=ORIGINAL ? 20 : InpBollingerPeriod,0,
                InpStrategy!=ORIGINAL ? 2.5 : InpBollingerDeviation,PRICE_CLOSE);
   if(InpStrategy==ORIGINAL)
   {
      if(InpOscillator==RSI)
         oscillator_handle=iRSI(_Symbol,PERIOD_M5,InpRSIPeriod,PRICE_CLOSE);
      else
         oscillator_handle=iStochastic(_Symbol,PERIOD_M5,InpStochasticK,InpStochasticD,InpStochasticSlowing,MODE_SMA,STO_LOWHIGH);
   }
   if(InpStrategy==BB_REENTRY && InpReentryADXMode!=ADX_OFF)
      adx_handle=iADX(_Symbol,PERIOD_M5,14);
   if(InpStrategy==BB_REENTRY && InpReentryMACDConfirm)
      macd_handle=iMACD(_Symbol,PERIOD_M5,InpMACDFast,InpMACDSlow,InpMACDSignal,PRICE_CLOSE);
   atr_handle=iATR(_Symbol,PERIOD_M5,InpStrategy!=ORIGINAL ? 14 : InpATRPeriod);
   if((InpStrategy==BB_REENTRY && InpReentryADXMode!=ADX_OFF && adx_handle==INVALID_HANDLE) ||
      (InpStrategy==BB_REENTRY && InpReentryMACDConfirm && macd_handle==INVALID_HANDLE) ||
      (InpStrategy==ATR_DEVIATION_REENTRY ? sma_handle==INVALID_HANDLE : bands==INVALID_HANDLE) || atr_handle==INVALID_HANDLE || (InpStrategy==ORIGINAL && oscillator_handle==INVALID_HANDLE)) return INIT_FAILED;
   reentry_state=NONE;
   reentry_outer_bar=0;
   g_last_signal_bar=BarOf(TimeCurrent()); // Do not evaluate a historical close on init/reinit.
   if(InpStrategy==ATR_DEVIATION_REENTRY)
      Log("INIT",StringFormat("estrategia=ATR_DEVIATION_REENTRY T=%.17g SMA=20 CLOSE ATR=14 M5 SL_ATR=%.10f ATR_max=%.10f entradas=1 TP=SMA20[1]",InpATRDeviationThreshold,InpReentrySLATR,InpATRMax),true);
   else if(InpStrategy==BB_WICK_REJECTION)
      Log("INIT",StringFormat("estrategia=BB_WICK_REJECTION modo=CLOSED_BAR wick_min=%.17g SL_ATR=%.10f BB=20/2.5 ATR=14 ATR_max=%.10f TP=SMA20[1] entradas=1",
          InpWickMinRatio,InpReentrySLATR,InpATRMax),true);
   else Log("INIT",InpStrategy==BB_REENTRY ?
       StringFormat("estrategia=BB_REENTRY modo=CLOSED_BAR BB=20/2.5 precio=CLOSE ATR=14 ATR_max=8 entradas=1 SL_ATR=%.10f salida=%s",InpReentrySLATR,InpReentryExitMode==EXIT_ATR_FIXED_2 ? "EXIT_ATR_FIXED_2" : (InpReentryExitMode==EXIT_HALF_SMA20_DYNAMIC ? "EXIT_HALF_SMA20_DYNAMIC" : (InpReentryExitMode==EXIT_OPPOSITE_BAND_DYNAMIC ? "EXIT_OPPOSITE_BAND_DYNAMIC" : (InpReentryExitMode==EXIT_HALF_SMA20_TRAIL_ATR ? "EXIT_HALF_SMA20_TRAIL_ATR" : "EXIT_SMA20_DYNAMIC")))) :
       "estrategia=ORIGINAL "+(InpOscillator==RSI ?
       StringFormat("oscilador=RSI periodo=%d compra=%.10f venta=%.10f timeframe=M5 precio=CLOSE",InpRSIPeriod,InpRSIBuyLevel,InpRSISellLevel) :
       StringFormat("oscilador=STOCHASTIC K=%d D=%d slowing=%d metodo=SMA precio=LOWHIGH compra=10 venta=90",InpStochasticK,InpStochasticD,InpStochasticSlowing)),true);
   if(InpStrategy!=ORIGINAL)
      Log("INIT",StringFormat("weekend_guard=%s bloqueo_min=%d cierre_min=%d",InpReentryWeekendGuard ? "true" : "false",
          InpWeekendEntryBlockMinutes,InpWeekendCloseMinutes),true);
   if(InpStrategy==BB_REENTRY)
      Log("INIT",InpReentryMACDConfirm ? StringFormat("MACD_confirm=true fast=%d slow=%d signal=%d M5 PRICE_CLOSE H=MAIN-SIGNAL shifts=1/2",InpMACDFast,InpMACDSlow,InpMACDSignal) : "MACD_confirm=false",true);
   if(InpStrategy==BB_REENTRY)
      Log("INIT",StringFormat("ADX_mode=%s ADX_period=14 MACD_confirm=%s",ReentryADXModeName(),InpReentryMACDConfirm ? "true" : "false"),true);
   if(InpStrategy==BB_REENTRY)
      Log("INIT",InpReentryBBWFilter ?
          (InpReentryBBWMode==BBW_BELOW_P70 ? "BBW_filter=true modo=BBW_BELOW_P70 referencia=2..101 n=100 indice=69 BBW1<P70" :
           "BBW_filter=true modo=BBW_NON_INCREASING BBW1<=BBW2") : "BBW_filter=false modo_efectivo=OFF",true);
   ResetHalfExit();
   ResetWeekendGuard();
   RefreshWeekendGuard();
   CheckOwnership();
   if(manual_required) return INIT_SUCCEEDED;
   if(!history_ok) { state=CLOSING_IDEA; exit_reason="Inicio con propiedad no verificable"; return INIT_SUCCEEDED; }
   if(OwnPositions()>0 || OwnOrders()>0)
   {
      had_exposure=true;
      idea_start=TimeCurrent(); TrackCurrent();
      BeginClose(WeekendGuardEnabled() && g_weekend_close_due ? "WEEKEND_GUARD" : "Limpieza de residuos propios al iniciar");
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
   if(sma_handle!=INVALID_HANDLE) IndicatorRelease(sma_handle);
   if(adx_handle!=INVALID_HANDLE) IndicatorRelease(adx_handle);
   if(macd_handle!=INVALID_HANDLE) IndicatorRelease(macd_handle);
   if(bands!=INVALID_HANDLE) IndicatorRelease(bands);
   if(oscillator_handle!=INVALID_HANDLE) IndicatorRelease(oscillator_handle);
   if(atr_handle!=INVALID_HANDLE) IndicatorRelease(atr_handle);
}
void OnTick()
{
   RefreshWeekendGuard();
   datetime previous_signal_bar=g_last_signal_bar;
   bool closed_bar_tick=((InpStrategy!=ORIGINAL || InpSignalMode==CLOSED_BAR) && TakeClosedBarOpportunity());
   bool deviation_gap=(InpStrategy==ATR_DEVIATION_REENTRY && closed_bar_tick && g_last_signal_bar!=previous_signal_bar+PeriodSeconds(PERIOD_M5));
   if(deviation_gap) ClearReentry("interrupcion entre oportunidades M5; evaluacion omitida");
   if(InpStrategy==BB_REENTRY && closed_bar_tick && g_last_signal_bar!=previous_signal_bar+PeriodSeconds(PERIOD_M5))
      ClearReentry("interrupcion entre oportunidades M5");
   g_request_cycle++;
   PruneManagementRetries();
   FlushExitReports();
   ReconcilePending(); CheckOwnership();
   if(!manual_required && history_ok && (state==WAITING_SIGNAL || state==COOLDOWN) && (OwnPositions()>0 || OwnOrders()>0))
   {
      idea_start=TimeCurrent(); had_exposure=true;
      e1_order=0; e2_order=0; ArrayResize(position_ids,0); TrackCurrent();
      ResetExcursions();
      BeginClose("Exposicion propia tardia fuera de una idea activa");
   }
   if(HalfExitMode()) { ObserveHalfExtreme(); double closed=0; ReconcileHalfExit(closed); }
   if(state==ACTIVE_IDEA || state==CLOSING_IDEA) InspectIdeaHistory();
   ObserveIdeaExcursions();
   if((InpStrategy==BB_REENTRY || InpStrategy==ATR_DEVIATION_REENTRY) && (manual_required || !history_ok || state==ACTIVE_IDEA || state==CLOSING_IDEA ||
      (state==COOLDOWN && TimeCurrent()<cooldown_until))) ClearReentry("idea activa, cierre, enfriamiento o gestion bloqueada");
   if(manual_required) { CloseStep(); return; }
   if(state==CLOSING_IDEA) { CloseStep(); SuperviseWeekendClose(); return; }
   if(!history_ok) return;
   datetime bar=iTime(_Symbol,PERIOD_M5,0);
   if(bar==0)
   {
      if(closed_bar_tick)
      {
         Log("REJECTED",InpStrategy==BB_WICK_REJECTION ? "estrategia=BB_WICK_REJECTION serie M5 no disponible; oportunidad descartada" :
             InpStrategy==BB_REENTRY ? "estrategia=BB_REENTRY serie M5 no disponible; oportunidad descartada" :
             "modo=CLOSED_BAR serie M5 no disponible; oportunidad descartada",true);
         ClearReentry("serie M5 no disponible");
      }
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
      if(state==ACTIVE_IDEA && !(InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_ATR_FIXED_2) && !(HalfExitMode() && g_half.trailing) && tp_bar!=bar)
      {
         double mid,upper,lower;
         if(TargetInputs(1,mid,upper,lower))
         {
            double previous=target; target=Target(mid,upper,lower); tp_bar=bar;
            if(!SamePrice(previous,target)) Log("TP_UPDATE",StringFormat("anterior=%.5f nuevo=%.5f",previous,target));
         }
         else Problem("Indicadores TP no disponibles; mantener supervision y reintentar");
      }
      if(state==ACTIVE_IDEA && HalfExitMode()) { HalfExitStep(); if(state==CLOSING_IDEA) CloseStep(); return; }
      if(state==ACTIVE_IDEA && HitTarget(q)) BeginClose(InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_ATR_FIXED_2 ? "TP fijo" : "TP dinamico");
      if(state==ACTIVE_IDEA) SyncTP();
      if(state==CLOSING_IDEA) CloseStep();
      return;
   }
   if(ArraySize(pending)>0 || OwnPositions()>0 || OwnOrders()>0 || ForeignExposure())
   {
      ClearReentry("exposicion o solicitud pendiente");
      return;
   }
   if(InpStrategy==ATR_DEVIATION_REENTRY)
   {
      if(WeekendGuardEnabled() && g_weekend_blocked) return;
      if(closed_bar_tick && !deviation_gap) EvaluateATRDeviationSignal();
      return;
   }
   if(InpStrategy==BB_WICK_REJECTION)
   {
      if(WeekendGuardEnabled() && g_weekend_blocked) return;
      if(closed_bar_tick) EvaluateWickSignal();
      return;
   }
   if(InpStrategy==BB_REENTRY)
   {
      if(WeekendGuardEnabled() && g_weekend_blocked) return;
      if(closed_bar_tick) EvaluateReentrySignal();
      return;
   }
   if(InpSignalMode==CLOSED_BAR)
   {
      if(closed_bar_tick) EvaluateClosedBarSignal();
      return;
   }
   double mid,upper,lower,k,atr_value;
   MqlRates current[1];
   if(!Bands(0,mid,upper,lower) || !Value(oscillator_handle,0,0,k) || !Value(atr_handle,0,1,atr_value) || CopyRates(_Symbol,PERIOD_M5,0,1,current)!=1)
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
      HalfExitTransaction(request,result);
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
   if(HalfExitMode()) { ObserveHalfExtreme(); double closed=0; ReconcileHalfExit(closed); }
   if(state==ACTIVE_IDEA || state==CLOSING_IDEA) InspectIdeaHistory();
   ObserveIdeaExcursions();
   FlushExitReports();
   // Execute reconciled actions on the next tick, not recursively in this handler.
}

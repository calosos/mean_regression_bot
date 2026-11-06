void next_tick(int seconds=6){partial_now+=seconds;g_request_cycle++;}
void start(int side=1){
 reset();ResetHalfExit();pending.clear();hist_orders.clear();hist_deals.clear();g_management_retries.clear();g_request_cycle=1;g_market_retry_after=0;
 test_owner=1;send_calls=0;send_code=TRADE_RETCODE_DONE;history_available=true;unknown_order=false;partial_now=1202;
 InpReentryExitMode=EXIT_HALF_SMA20_TRAIL_ATR;InpReentrySLATR=2;
 OpenIdea(side,2,side>0 ? 2502:2498,2600,2400);
 assert(state==ACTIVE_IDEA && pos_tp==0 && entries==1 && pending_calls==0 && g_half.position_id==777);
 hist_deals.push_back({1,e1_order,777,DEAL_ENTRY_IN,DEAL_REASON_EXPERT,pos_volume,0,-.5,0,0});
}
void trigger(){quote_bid=direction>0 ? 2502:2497.8;quote_ask=quote_bid+.2;next_tick();HalfExitStep();}
int main(){
 double part=0;
 for(int units=1;units<=100;units++){
  double v=NormalizeDouble(units*.01,8);bool split=HalfSplit(v,part);
  assert(split==(units>=2));if(split){assert(SamePrice(part,NormalizeDouble((units/2)*.01,8)));assert(HalfVolumeValid(v-part));}
 }
 for(bool model:{false,true})for(int side:{1,-1}){
  netting=model;start(side);double initial=g_half.initial_volume,sl=g_sl;
  assert(initial==.15);trigger();assert(send_calls==1 && g_half.pending && !g_half.trailing);
  assert(SamePrice(last_request.volume,.07));
  for(int n=0;n<5;n++){next_tick();HalfExitStep();}assert(send_calls==1 && pos_sl==sl);
  // Position volume may arrive before history. Never activate trailing on volume alone.
  settle(.07);hist_deals.pop_back();next_tick();HalfExitStep();assert(g_half.pending && !g_half.trailing && send_calls==1);
  hist_deals.push_back({1000+serial,serial,777,DEAL_ENTRY_OUT,DEAL_REASON_EXPERT,.07,10,-1,0,0});
  quote_bid=side>0 ? 2503.37:2496.37;quote_ask=quote_bid+.2;
  double reference=side>0 ? quote_bid:quote_ask;
  next_tick();HalfExitStep();assert(g_half.trailing && !g_half.pending && SamePrice(pos_volume,.08));
  assert(g_half.extreme==reference && g_sl==Price(reference-side*2) && pos_sl==g_sl && pos_tp==0 && frozen_atr==2);
  double after=g_sl;InspectIdeaHistory();assert(state==ACTIVE_IDEA && SamePrice(realized,8.5));
  HalfExitTransaction(last_request,last_result);next_tick();HalfExitStep();assert(send_calls==1 && g_half.trailing && g_sl==after);
  quote_bid+=side*2;quote_ask+=side*2;next_tick();HalfExitStep();assert(side>0 ? g_sl>after:g_sl<after);after=g_sl;
  quote_bid-=side;quote_ask-=side;next_tick();HalfExitStep();assert(g_sl==after && pos_sl==after);
  // The final SL deal must close the whole idea and include both profits/costs.
  hist_deals.push_back({9999,999,777,DEAL_ENTRY_OUT,DEAL_REASON_SL,.08,-2,0,0,0});position=false;
  InspectIdeaHistory();assert(state==CLOSING_IDEA && SamePrice(realized,6.5));
 }
 start();InpRiskBaseUSD=4000; // Use a valid one-step position to exercise fallback.
 g_half.initial_volume=pos_volume=.01;trigger();assert(state==CLOSING_IDEA && send_calls==0);
 assert(std::find(entry_log_tags.begin(),entry_log_tags.end(),"PARTIAL_NOT_POSSIBLE")!=entry_log_tags.end());
 start();send_code=TRADE_RETCODE_MARKET_CLOSED;trigger();assert(!g_half.pending && send_calls==1);
 for(int i=0;i<4;i++){next_tick(1);HalfExitStep();}assert(send_calls==1);send_code=TRADE_RETCODE_DONE;
 next_tick(1);HalfExitStep();assert(send_calls==2 && g_half.pending);
 // Unknown request stays locked; late order identity is recovered by comment.
 start();unknown_order=true;send_code=TRADE_RETCODE_TIMEOUT;trigger();assert(g_half.pending && g_half.order==0);
 for(int i=0;i<20;i++){next_tick();HalfExitStep();}assert(send_calls==1);
 settle(.07);next_tick();HalfExitStep();assert(g_half.trailing && send_calls==1 && HalfKnownOrder(serial));
 // IOC partial execution: only the missing volume is sent on the next attempt.
 start();trigger();settle(.03);next_tick();HalfExitStep();assert(send_calls==2 && SamePrice(last_request.volume,.04) && !g_half.trailing);
 settle(.04);next_tick();HalfExitStep();assert(g_half.trailing && SamePrice(pos_volume,.08));
 // Modified SL is not credited on an error/uncertainty until the broker confirms it.
 start();trigger();settle(.07);next_tick();HalfExitStep();double old=g_sl;
 quote_bid+=2;quote_ask+=2;modify_code=TRADE_RETCODE_MARKET_CLOSED;next_tick();HalfExitStep();assert(g_sl==old && pos_sl==old);
 modify_code=TRADE_RETCODE_TIMEOUT;next_tick();HalfExitStep();assert(g_sl==old && pos_sl==old && locks==1);
 double requested=g_half.requested_sl;pos_sl=requested;locks=0;pending.clear();modify_code=TRADE_RETCODE_DONE;next_tick();HalfExitStep();assert(g_sl==requested);
 // Foreign/mixed position never receives a partial or trailing modification.
 for(int owner:{0,2}){start();test_owner=owner;trigger();assert(send_calls==0);}
 start();manual_required=true;trigger();assert(send_calls==0);
 start();trigger();history_available=false;settle(.07);next_tick();HalfExitStep();assert(!g_half.trailing && send_calls==1);
 history_available=true;next_tick();HalfExitStep();assert(g_half.trailing && send_calls==1);
 std::cout<<"PASS: partial splits/buy/sell/hedging/netting request payload, no broker TP, delayed history/volume, duplicate events, rejection/retry, unknown order recovery, IOC remainder, trailing extrema/SL confirmation, own-deal PnL and ownership protection\n";

 // Broker minimum/step boundaries and partial execution too small to complete.
 volume_step=.05;volume_min=.15;assert(!HalfSplit(.20,part));assert(HalfSplit(.30,part) && SamePrice(part,.15));
 volume_step=.01;volume_min=.01;
 start();pos_tp=target;trigger();assert(pos_tp==0 && send_calls==0);next_tick();HalfExitStep();assert(send_calls==1);
 start();trigger();settle(.07,false);next_tick();HalfExitStep();assert(g_half.pending && !g_half.trailing && send_calls==1);
 hist_orders.back().state=ORDER_STATE_FILLED;next_tick();HalfExitStep();assert(g_half.trailing && send_calls==1);
 std::cout<<"PASS: broker split minima/steps, removal of position TP, nonterminal order cannot activate trailing\n";

 // A concurrent SL exit may reduce more than the partial; reconcile all exits
 // before releasing the partial lock and let the normal close path finish.
 start();trigger();settle(.07);hist_deals.push_back({9998,998,777,DEAL_ENTRY_OUT,DEAL_REASON_SL,.03,0,0,0,0});pos_volume-=.03;
 next_tick();InspectIdeaHistory();assert(state==CLOSING_IDEA);
 double total=0;assert(ReconcileHalfExit(total) && !g_half.pending && SamePrice(total,.07) && SamePrice(pos_volume,.05));
 std::cout<<"PASS: simultaneous SL exit reconciles with partial without a permanent close lock\n";

 start();trigger();settle(.07);next_tick();HalfExitStep();double before=g_sl;
 history_available=false;quote_bid=2508.125;quote_ask=2508.325;next_tick();HalfExitStep();assert(g_half.extreme==2508.125 && g_sl==before);
 history_available=true;quote_bid=2508.1;quote_ask=2508.3;next_tick();HalfExitStep();assert(g_sl==Price(2508.125-2));
 std::cout<<"PASS: trailing keeps observing quote extrema during a temporary history outage, retaining old SL until safe reconciliation\n";

 start();trigger();assert(Locked(42,false) && Locked(43,false)); // same immutable position id after ticket rollover
 settle(.07);next_tick();HalfExitStep();assert(!Locked(42,false));
 std::cout<<"PASS: unresolved partial locks full-close/modify operations by immutable position identity as well as ticket\n";
}

int main(){
 for(int side:{1,-1}){
  reset();double mid=side==1 ? 2502:2498;
  OpenIdea(side,2,mid,2600,2400);
  assert(state==ACTIVE_IDEA && buy_calls+sell_calls==1 && pending_calls==0 && e2_order==0 && entries==1);
  assert(SamePrice(lot,.1) && SamePrice(g_sl,2500-side*6) && SamePrice(pos_sl,g_sl));
  assert(target==mid && pos_tp==mid && entry_logs==1);
  double sl=g_sl;target=side==1 ? 2503:2497;SyncTP();assert(pos_tp==target && g_sl==sl && pos_sl==sl);
  int previous=modify_calls;SyncTP();assert(modify_calls==previous); // unchanged TP sends no request
  target=side==1 ? 2490:2510;SyncTP();assert(state==CLOSING_IDEA && pos_sl==sl);
 }
 reset();OpenIdea(1,2,2499,2600,2400);assert(state==CLOSING_IDEA && pending_calls==0 && pos_sl==2494 && entry_logs==1);
 reset();OpenIdea(1,2,2500.004,2600,2400);assert(state==CLOSING_IDEA && pending_calls==0); // normalized target reached
 reset();OpenIdea(-1,2,2500.2,2600,2400);assert(state==CLOSING_IDEA && pending_calls==0);
 reset();modify_code=TRADE_RETCODE_INVALID_STOPS;OpenIdea(1,2,2502,2600,2400);
 assert(state==ACTIVE_IDEA && pos_sl==2494 && pos_tp==0 && modify_calls==2 && pending_calls==0);
 modify_code=TRADE_RETCODE_DONE;SyncTP();assert(pos_tp==2502 && pos_sl==2494);
 reset();modify_code=TRADE_RETCODE_TIMEOUT;OpenIdea(1,2,2502,2600,2400);assert(state==CLOSING_IDEA && locks==1 && pending_calls==0);
 reset();entry_code=TRADE_RETCODE_TIMEOUT;OpenIdea(1,2,2502,2600,2400);assert(state==CLOSING_IDEA && locks==1 && buy_calls==1 && pending_calls==0);
 reset();entry_code=TRADE_RETCODE_DONE_PARTIAL;OpenIdea(1,2,2502,2600,2400);assert(state==CLOSING_IDEA && buy_calls==1 && pending_calls==0);
 // For BB one calc at min volume, one at chosen volume, then one after execution.
 reset();calc_fail_at=3;OpenIdea(1,2,2502,2600,2400);assert(position && state==CLOSING_IDEA && pending_calls==0);
 reset();pos_price=2500.005;tick_size=.05;volume_step=.01;volume_min=.01;
 // Rounded execution SL can make risk exceed a budget exactly spent before execution.
 InpRiskBaseUSD=24004;quote_ask=2500;OpenIdea(1,2,2502,2600,2400);
 assert(position && state==CLOSING_IDEA && pending_calls==0);tick_size=.01;
 reset();fail_calc=true;OpenIdea(1,2,2502,2600,2400);assert(!position && buy_calls==0);
 reset();OpenIdea(1,0,2502,2600,2400);assert(buy_calls==0);
 reset();InpATRMax=100;OpenIdea(1,8.01,2502,2600,2400);assert(buy_calls==0);
 reset();foreign=true;OpenIdea(1,2,2502,2600,2400);assert(buy_calls==0);
 reset();InpStrategy=ORIGINAL;OpenIdea(1,2,2550,2600,2400);
 assert(state==ACTIVE_IDEA && pending_calls==1 && entries==1 && e2_order!=0 && SamePrice(lot,.06));
 assert(SamePrice(target,2535));
 std::cout<<"PASS: actual OpenIdea/SL/TP: one entry, no E2, 3ATR risk, real execution recheck, TP fallback, fixed SL, uncertainty/partials and failures\n";

 for(double multiplier:{2.,3.})for(int side:{1,-1}){
  reset();InpReentrySLATR=multiplier;
  OpenIdea(side,2,side==1 ? 2502:2498,2600,2400);
  assert(state==ACTIVE_IDEA && entries==1 && pending_calls==0);
  assert(SamePrice(lot,multiplier==2 ? .15:.10));
  assert(SamePrice(g_sl,pos_price-side*multiplier*2) && pos_sl==g_sl);
  double risk;assert(Risk(lot,pos_price,0,g_sl,risk) && risk<=Budget());
 }
 reset();InpReentrySLATR=2;pos_price=2500.004;quote_ask=2500;InpRiskBaseUSD=24004;
 OpenIdea(1,2,2502,2600,2400);
 assert(position && state==CLOSING_IDEA && pending_calls==0); // actual normalized risk exceeds 60.01
 reset();InpStrategy=ORIGINAL;InpReentrySLATR=2;OpenIdea(1,2,2550,2600,2400);
 assert(pending_calls==1 && SamePrice(lot,.06) && g_sl==2494);
 std::cout<<"PASS: SL multipliers 2/3 size for unchanged budget, set real-fill SL, recheck normalized risk; ORIGINAL stays 3 ATR\n";

 for(int side:{1,-1}){
  reset();InpStrategy=BB_WICK_REJECTION;InpReentrySLATR=2;OpenIdea(side,2,side==1 ? 2502:2498,2600,2400);
  assert(state==ACTIVE_IDEA && entries==1 && pending_calls==0 && e2_order==0 && SamePrice(lot,.15));
  assert(SamePrice(g_sl,2500-side*4) && pos_sl==g_sl && target==(side==1 ? 2502:2498));
 }
 reset();InpStrategy=BB_WICK_REJECTION;InpATRMax=5;OpenIdea(1,6,2502,2600,2400);assert(buy_calls==0);
 std::cout<<"PASS: V6 actual OpenIdea one entry, 2ATR SL/volume, SMA target, configured ATR maximum\n";

 reset();InpStrategy=ATR_DEVIATION_REENTRY;InpReentrySLATR=2;OpenIdea(1,2,2502,0,0);
 assert(state==ACTIVE_IDEA && entries==1 && pending_calls==0 && e2_order==0 && SamePrice(lot,.15) && pos_sl==2496 && target==2502);
 std::cout<<"PASS: ATR deviation actual entry risk/SL for single entry and SMA TP\n";

 for(int side:{1,-1}){
  reset();InpReentryExitMode=EXIT_ATR_FIXED_2;InpReentrySLATR=2;pos_price=2500.37;
  OpenIdea(side,2,side==1 ? 2490:2510,2600,2400); // SMA already beyond current price must not close fixed idea.
  double expected=Price(pos_price+side*4),stop=Price(pos_price-side*4);
  assert(state==ACTIVE_IDEA && target==expected && pos_tp==expected && pos_sl==stop && entries==1 && pending_calls==0);
  assert(target!=Price((side==1 ? quote_ask:quote_bid)+side*4) && frozen_atr==2);
  int previous=modify_calls;SyncTP();assert(modify_calls==previous && pos_sl==stop);
  if(side==1)quote_bid=expected;else quote_ask=expected;
  SyncTP();assert(state==CLOSING_IDEA && pos_sl==stop);
 }
 reset();InpReentryExitMode=EXIT_ATR_FIXED_2;modify_code=TRADE_RETCODE_INVALID_STOPS;
 OpenIdea(1,2,2490,2600,2400);assert(state==ACTIVE_IDEA && target==2504 && pos_sl==2494 && pos_tp==0);
 modify_code=TRADE_RETCODE_DONE;SyncTP();assert(pos_tp==2504 && pos_sl==2494);
 for(auto strategy:{BB_WICK_REJECTION,ATR_DEVIATION_REENTRY}){
  reset();InpStrategy=strategy;InpReentryExitMode=EXIT_ATR_FIXED_2;OpenIdea(1,2,2502,2600,2400);assert(target==2502 && state==ACTIVE_IDEA);
 }
 std::cout<<"PASS: S3 fixed TP buys/sells from actual fill and frozen ATR, normalized, logical fallback/retry, fixed SL, no repeated modification, other strategies ignore selector\n";

 reset();InpReentryExitMode=EXIT_ATR_FIXED_2;tick_size=.05;pos_price=2500.37;OpenIdea(1,2,2490,2600,2400);
 assert(state==ACTIVE_IDEA && target==2504.35 && pos_tp==2504.35);tick_size=.01;
 reset();InpReentryExitMode=EXIT_ATR_FIXED_2;modify_code=TRADE_RETCODE_INVALID_STOPS;OpenIdea(1,2,2490,2600,2400);
 modify_code=TRADE_RETCODE_DONE;SyncTP();
 assert(std::find(entry_log_tags.begin(),entry_log_tags.end(),"TP_SYNC")!=entry_log_tags.end());
 assert(std::find(entry_log_tags.begin(),entry_log_tags.end(),"TP_UPDATE")==entry_log_tags.end());
 std::cout<<"PASS: S3 rounds TP to tick and distinguishes server synchronization from target changes\n";

 for(int side:{1,-1}){
  reset();InpReentryExitMode=EXIT_HALF_SMA20_DYNAMIC;InpReentrySLATR=2;pos_price=2500.37;
  double mid=side==1 ? 2504.37:2496.37;
  OpenIdea(side,2,mid,2600,2400);double original_entry=entry_price,stop=g_sl;
  assert(state==ACTIVE_IDEA && target==Price(pos_price+0.5*(mid-pos_price)) && pos_tp==target && pos_sl==stop);
  assert(target!=Price((side==1 ? quote_ask:quote_bid)+.5*(mid-(side==1 ? quote_ask:quote_bid))));
  target=Target(side==1 ? 2506.37:2494.37,2600,2400);SyncTP();
  assert(entry_price==original_entry && target==Price(original_entry+side*3) && g_sl==stop && pos_sl==stop);
  assert(std::find(entry_log_tags.begin(),entry_log_tags.end(),"TP_UPDATE")!=entry_log_tags.end());
 }
 reset();InpReentryExitMode=EXIT_HALF_SMA20_DYNAMIC;modify_code=TRADE_RETCODE_INVALID_STOPS;OpenIdea(1,2,2504,2600,2400);
 assert(state==ACTIVE_IDEA && target==2502 && pos_tp==0 && pos_sl==2494);
 modify_code=TRADE_RETCODE_DONE;SyncTP();assert(pos_tp==2502 && pos_sl==2494);
 for(auto strategy:{BB_WICK_REJECTION,ATR_DEVIATION_REENTRY}){
  reset();InpStrategy=strategy;InpReentryExitMode=EXIT_HALF_SMA20_DYNAMIC;OpenIdea(1,2,2502,2600,2400);assert(target==2502);
 }
 std::cout<<"PASS: half SMA buys/sells use actual E1 fixed reference, fallback/server retry, fixed SL, TP_UPDATE and other-strategy isolation\n";

 for(int side:{1,-1}){
  reset();InpReentryExitMode=EXIT_OPPOSITE_BAND_DYNAMIC;InpReentrySLATR=2;
  OpenIdea(side,2,2500,2505.127,2495.123);
  assert(state==ACTIVE_IDEA && target==Price(side==1 ? 2505.127:2495.123) && pos_tp==target && pending_calls==0);
  double sl=g_sl;target=Target(2500,2506,2494);SyncTP();assert(pos_tp==target && pos_sl==sl && g_sl==sl);
 }
 reset();InpReentryExitMode=EXIT_OPPOSITE_BAND_DYNAMIC;OpenIdea(1,2,2502,2499,2490);assert(state==CLOSING_IDEA && pending_calls==0);
 reset();InpReentryExitMode=EXIT_OPPOSITE_BAND_DYNAMIC;OpenIdea(-1,2,2498,2510,2501);assert(state==CLOSING_IDEA && pending_calls==0);
 reset();InpReentryExitMode=EXIT_OPPOSITE_BAND_DYNAMIC;modify_code=TRADE_RETCODE_INVALID_STOPS;OpenIdea(1,2,2500,2505,2495);
 assert(state==ACTIVE_IDEA && target==2505 && pos_tp==0 && pos_sl==2494);
 modify_code=TRADE_RETCODE_DONE;SyncTP();assert(pos_tp==2505 && pos_sl==2494);
 for(auto strategy:{BB_WICK_REJECTION,ATR_DEVIATION_REENTRY}){
  reset();InpStrategy=strategy;InpReentryExitMode=EXIT_OPPOSITE_BAND_DYNAMIC;OpenIdea(1,2,2502,2505,2495);assert(target==2502);
 }
 std::cout<<"PASS: opposite-band entry targets both sides, normalization, initial hit close, logical fallback/retry, SL intact, strategy isolation\n";
}

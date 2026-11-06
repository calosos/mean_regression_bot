// Deterministic regression scenarios; production functions are injected from the current EA.
void tick(datetime t){now=t;datetime bar=t/300*300;candles[0].time=bar;candles[1].time=bar-300;candles[2].time=bar-600;OnTick();}
void reset(SignalMode mode=CLOSED_BAR){
 closed_mid=200;reentry_state=NONE;reentry_outer_bar=0;
 InpSignalMode=mode;state=WAITING_SIGNAL;now=1000;g_last_signal_bar=900;cooldown_until=0;processed_buy=0;processed_sell=0;
 own_positions=own_orders=close_calls=reconcile_calls=problems=rejected_logs=signal_logs=tp_syncs=0;
 manual_required=false;history_ok=true;foreign=false;accept_open=false;pending.clear();opens.clear();
 series_ready=rates_ready=closed_bands_ready=tp_bands_ready=stoch_ready=atr_ready=true;
 k_current=9;k_closed=9;atr_closed=2;profit=0;g_sl=0;target=100;
 candles[0]={900,89,111,80};candles[1]={600,179,221,190};
 band_reads.clear();stoch_reads.clear();atr_reads.clear();rate_reads.clear();
}
int main(){
 reset();tick(1000);tick(1100);assert(opens.empty());tick(1202);
 assert(opens.size()==1 && opens[0].time==1202 && opens[0].atr==2 && opens[0].mid==100 && opens[0].side==1);
 assert(processed_buy==900 && band_reads==std::vector<int>({1,0}) && stoch_reads==std::vector<int>({1}) && atr_reads==std::vector<int>({1}) && rate_reads==std::vector<int>({1}));
 for(int t=1203;t<1500;t++)tick(t);assert(opens.size()==1);tick(1500);assert(opens.size()==2 && processed_buy==1200);
 reset();k_closed=91;tick(1200);assert(opens.size()==1 && opens[0].side==-1 && processed_sell==900);
 for(double close:{180.,220.,179.,221.}){reset();candles[1].close=close;tick(1200);assert(opens.empty());}
 for(double k:{10.,50.,90.}){reset();k_current=9;k_closed=k;tick(1200);assert(opens.empty());}
 reset();candles[1].low=181;tick(1200);assert(opens.empty());
 reset();k_closed=91;candles[1].high=219;tick(1200);assert(opens.empty());
 reset();candles[1].low=180;tick(1200);assert(opens.size()==1);
 reset();k_closed=91;candles[1].high=220;tick(1200);assert(opens.size()==1);
 std::cout<<"PASS: CLOSED_BAR buy/sell, strict close/K boundaries, inclusive band touch, ATR[1], initial TP[0], first available tick, no repeated bar\n";
 for(int failure=0;failure<6;failure++){
  reset();
  switch(failure){case 0:rates_ready=false;break;case 1:closed_bands_ready=false;break;case 2:tp_bands_ready=false;break;case 3:stoch_ready=false;break;case 4:atr_ready=false;break;case 5:series_ready=false;break;}
  tick(1200);assert(opens.empty() && rejected_logs==1);
  series_ready=rates_ready=closed_bands_ready=tp_bands_ready=stoch_ready=atr_ready=true;
  tick(1201);tick(1400);assert(opens.empty());tick(1500);assert(opens.size()==1);
 }
 reset();state=ACTIVE_IDEA;own_positions=1;tick(1200);state=WAITING_SIGNAL;own_positions=0;tick(1201);assert(opens.empty());tick(1500);assert(opens.size()==1);
 reset();state=COOLDOWN;cooldown_until=1201;tick(1200);tick(1201);assert(opens.empty());tick(1500);assert(opens.size()==1);
 reset();state=COOLDOWN;cooldown_until=1200;tick(1200);assert(opens.size()==1);
 reset();foreign=true;tick(1200);foreign=false;tick(1201);assert(opens.empty());tick(1500);assert(opens.size()==1);
 reset();tick(1200);assert(opens.size()==1);opens.clear();g_last_signal_bar=BarOf(1200);tick(1200);tick(1201);assert(opens.empty());tick(1500);assert(opens.size()==1);
 reset();tick(2105);assert(opens.size()==1 && processed_buy==1800);
 std::cout<<"PASS: no historical replay on initialization/restart, missing-data opportunities discarded, active/cooldown/foreign skips not recovered, gap evaluates latest closed bar only\n";
 reset(INTRABAR);tick(1000);assert(opens.size()==1 && processed_buy==900 && opens[0].side==1);
 assert(stoch_reads==std::vector<int>({0}) && rate_reads==std::vector<int>({0}) && atr_reads==std::vector<int>({1}));
 tick(1001);assert(opens.size()==1);k_current=91;tick(1002);assert(opens.size()==2 && opens[1].side==-1);
 reset(INTRABAR);stoch_ready=false;tick(1000);assert(opens.empty());stoch_ready=true;tick(1001);assert(opens.size()==1);
 reset(INTRABAR);state=ACTIVE_IDEA;own_positions=1;profit=-63;tick(1000);assert(state==CLOSING_IDEA && close_calls==1);
 std::cout<<"PASS: INTRABAR immediate outside-band signal, both directions, shift[0], deduplication, same-bar retry after unavailable data, monetary risk supervision\n";

 // RSI uses independent mocked buffer values; Stochastic is deliberately opposite.
 InpOscillator=RSI;
 for(auto mode:{INTRABAR,CLOSED_BAR}){
  for(double value:{0.,29.999,30.,50.,70.,70.001,100.}){
   reset(mode);rsi_current=rsi_closed=value;k_current=k_closed=value<50 ? 99:1;
   tick(mode==INTRABAR ? 1000:1200);
   int expected=value<30 ? 1:(value>70 ? -1:0);
   assert(opens.size()==(expected==0 ? 0:1));
   if(expected){assert(opens[0].side==expected && opens[0].atr==2);assert(stoch_reads==std::vector<int>({mode==INTRABAR ? 0:1}));}
  }
  reset(mode);rsi_current=29;rsi_closed=71;tick(mode==INTRABAR ? 1000:1200);
  assert(opens.size()==1 && opens[0].side==(mode==INTRABAR ? 1:-1));
  tick(mode==INTRABAR ? 1001:1201);assert(opens.size()==1);
  for(int failure=0;failure<6;failure++){
   reset(mode);rsi_current=rsi_closed=29;
   switch(failure){case 0:rates_ready=false;break;case 1:if(mode==CLOSED_BAR)closed_bands_ready=false;else tp_bands_ready=false;break;case 2:tp_bands_ready=false;break;case 3:stoch_ready=false;break;case 4:atr_ready=false;break;case 5:if(mode==CLOSED_BAR)series_ready=false;else rates_ready=false;break;}
   tick(mode==INTRABAR ? 1000:1200);assert(opens.empty());
   series_ready=rates_ready=closed_bands_ready=tp_bands_ready=stoch_ready=atr_ready=true;
   tick(mode==INTRABAR ? 1001:1201);assert(opens.size()==(mode==INTRABAR ? 1:0));
  }
 }
 InpRSIBuyLevel=35;InpRSISellLevel=65;reset();rsi_closed=34;tick(1200);assert(opens.size()==1 && opens[0].side==1);
 reset();rsi_closed=66;tick(1200);assert(opens.size()==1 && opens[0].side==-1);
 std::cout<<"PASS: RSI strict/custom thresholds, independent buffers, shifts, ATR[1], deduplication and missing data in both modes\n";

 InpStrategy=BB_REENTRY;
 for(auto ignored_mode:{INTRABAR,CLOSED_BAR}){
  reset(ignored_mode);candles[1].close=190;tick(1202);assert(reentry_state==NONE && opens.empty()); // wick alone
  candles[1].close=179;tick(1503);assert(reentry_state==WAIT_BUY_REENTRY && reentry_outer_bar==1200 && opens.empty());
  tick(1504);tick(1799);assert(opens.empty());
  tick(1801);assert(reentry_outer_bar==1200 && opens.empty()); // same outside side preserves first bar
  candles[1].close=180;tick(2101);assert(reentry_state==WAIT_BUY_REENTRY && opens.empty());
  candles[1].close=220;tick(2401);assert(reentry_state==WAIT_BUY_REENTRY && opens.empty());
  candles[1].low=190;candles[1].high=200;candles[1].close=195;tick(2707);
  assert(opens.size()==1 && opens[0].side==1 && opens[0].mid==200 && opens[0].atr==2 && reentry_state==NONE);
  assert(stoch_reads.empty());for(auto shift:band_reads)assert(shift==1);for(auto shift:atr_reads)assert(shift==1);
  tick(2708);tick(3000);assert(opens.size()==1); // no fresh preparation
  reset(ignored_mode);candles[1].close=179;tick(1200);candles[1].close=221;tick(1500);
  assert(reentry_state==WAIT_SELL_REENTRY && reentry_outer_bar==1200 && opens.empty());
  candles[1].close=200;tick(1800);assert(opens.size()==1 && opens[0].side==-1 && reentry_state==NONE);
  for(int failure=0;failure<5;failure++){
   reset(ignored_mode);candles[1].close=179;tick(1200);assert(reentry_state==WAIT_BUY_REENTRY);
   switch(failure){case 0:rates_ready=false;break;case 1:closed_bands_ready=false;break;case 2:atr_ready=false;break;case 3:series_ready=false;break;case 4:break;}
   if(failure==4){now=1502;candles[0].time=1500;candles[1].time=900;OnTick();}else tick(1502);
   assert(reentry_state==NONE && opens.empty());
   series_ready=rates_ready=closed_bands_ready=atr_ready=true;candles[1].close=200;
   tick(1503);tick(1800);assert(opens.empty());
  }
  reset(ignored_mode);candles[1].close=179;tick(1200);candles[1].close=200;tick(2105);
  assert(reentry_state==NONE && opens.empty()); // skipped opportunities clear the sequence
  for(int block=0;block<4;block++){
   reset(ignored_mode);candles[1].close=179;tick(1200);
   if(block==0){state=ACTIVE_IDEA;own_positions=1;}
   if(block==1){state=COOLDOWN;cooldown_until=1801;}
   if(block==2){state=CLOSING_IDEA;}
   if(block==3){foreign=true;}
   tick(1500);assert(reentry_state==NONE && opens.empty());
   state=WAITING_SIGNAL;own_positions=0;foreign=false;candles[1].close=200;
   tick(1501);tick(1800);assert(opens.empty());
  }
  reset(ignored_mode);candles[1].close=179;tick(1000);assert(reentry_state==NONE); // init reference only
 }
 std::cout<<"PASS: BB reentry wick/outside/inside/opposite/equality transitions, no touch, both ignored modes, continuity, missing data and blocked states\n";

 reset();candles[1].close=179;tick(1200);assert(reentry_state==WAIT_BUY_REENTRY);
 Cooldown(1201);assert(reentry_state==NONE && cooldown_until==1800);
 reset();state=ACTIVE_IDEA;own_positions=1;direction=1;g_sl=50;target=150;tp_bar=900;
 tick(1207);assert(target==200 && tp_bar==1200 && g_sl==50 && opens.empty() && reentry_state==NONE);
 closed_mid=205;tick(1500);assert(target==205 && g_sl==50);
 closed_mid=199;tick(1800);assert(target==199 && g_sl==50 && stoch_reads.empty());
 assert(band_reads==std::vector<int>({1,1,1}));
 std::cout<<"PASS: BB actual Cooldown clears preparation; active OnTick updates SMA[1] in both directions without changing SL\n";

 InpStrategy=BB_REENTRY;InpReentryMACDConfirm=true;
 for(int side:{1,-1})for(double h1:{-2.,-1.,0.,1.,2.})for(double h2:{-2.,-1.,0.,1.,2.}){
  reset();macd_reads.clear();macd_values[0][1]=10+h1;macd_values[1][1]=10;macd_values[0][2]=20+h2;macd_values[1][2]=20;
  candles[1].close=side==1 ? 179:221;tick(1200);assert(opens.empty() && macd_reads.empty());
  candles[1].close=200;tick(1500);
  bool expected=side==1 ? h1<0 && h1>h2 : h1>0 && h1<h2;
  assert(opens.size()==(expected ? 1:0) && reentry_state==NONE);
  if(expected)assert(opens[0].side==side && opens[0].atr==2 && opens[0].mid==200);
  assert((macd_reads==std::vector<std::pair<int,int>>{{0,1},{1,1},{0,2},{1,2}}));
  tick(1501);tick(1800);assert(opens.size()==(expected ? 1:0));
 }
 for(int buffer:{0,1})for(int shift:{1,2}){
  reset();candles[1].close=179;tick(1200);macd_ready[buffer][shift]=false;candles[1].close=200;tick(1500);
  assert(opens.empty() && reentry_state==NONE);macd_ready[buffer][shift]=true;
  tick(1501);tick(1800);assert(opens.empty());
 }
 reset();InpReentryMACDConfirm=false;macd_reads.clear();candles[1].close=179;tick(1200);candles[1].close=200;tick(1500);
 assert(opens.size()==1 && macd_reads.empty());
 std::cout<<"PASS: MACD H=MAIN-SIGNAL both directions/strict equalities, shifts1/2, consume rejection/missing buffers, no late entry and disabled regression\n";

 InpStrategy=BB_REENTRY;InpReentryMACDConfirm=false;
 for(auto mode:{ADX_OFF,ADX_BELOW_25,ADX_BELOW_20,ADX_BELOW_25_FALLING})
 for(int side:{1,-1})for(double a1:{19.999,20.,24.999,25.,26.})for(double a2:{19.,24.999,25.,27.}){
  reset();InpReentryADXMode=mode;adx_reads.clear();adx_values[1]=a1;adx_values[2]=a2;
  candles[1].close=side==1 ? 179:221;tick(1200);assert(adx_reads.empty());
  candles[1].close=200;tick(1500);
  bool expected=mode==ADX_OFF || (mode==ADX_BELOW_20 ? a1<20 : a1<25 && (mode!=ADX_BELOW_25_FALLING || a1<a2));
  assert(opens.size()==(expected ? 1:0) && reentry_state==NONE);
  if(mode==ADX_OFF)assert(adx_reads.empty());
  else assert(adx_reads==(mode==ADX_BELOW_25_FALLING ? std::vector<int>{1,2}:std::vector<int>{1}));
  tick(1501);tick(1800);assert(opens.size()==(expected ? 1:0));
 }
 for(int shift:{1,2}){
  reset();InpReentryADXMode=ADX_BELOW_25_FALLING;adx_values[1]=19;adx_values[2]=21;
  candles[1].close=179;tick(1200);adx_ready[shift]=false;candles[1].close=200;tick(1500);
  assert(opens.empty() && reentry_state==NONE);adx_ready[shift]=true;
  tick(1501);tick(1800);assert(opens.empty());
 }
 for(bool macd_pass:{false,true})for(bool adx_pass:{false,true}){
  reset();InpReentryMACDConfirm=true;InpReentryADXMode=ADX_BELOW_25;
  macd_values[0][1]=macd_pass ? -1:1;macd_values[1][1]=0;macd_values[0][2]=-2;macd_values[1][2]=0;
  adx_values[1]=adx_pass ? 19:25;candles[1].close=179;tick(1200);candles[1].close=200;tick(1500);
  assert(opens.size()==(macd_pass && adx_pass ? 1:0));
 }
 reset();InpReentryMACDConfirm=false;InpReentryADXMode=ADX_BELOW_25;adx_reads.clear();
 state=ACTIVE_IDEA;own_positions=1;target=200;g_sl=50;adx_values[1]=99;tick(1200);
 assert(state==ACTIVE_IDEA && adx_reads.empty());
 InpReentryADXMode=ADX_OFF;
 std::cout<<"PASS: four ADX modes both directions, strict thresholds/falling, closed shifts only, rejection/missing data consumed, AND with MACD and active management isolation\n";

 InpStrategy=BB_REENTRY;InpReentryADXMode=ADX_OFF;InpReentryMACDConfirm=false;InpReentryBBWFilter=true;
 for(int side:{1,-1})for(double width2:{10.,20.,40.}){
  reset();bbw_mid2=100;bbw_upper2=100+width2/2;bbw_lower2=100-width2/2;
  candles[1].close=side==1 ? 179:221;tick(1200);assert(opens.empty());
  assert(std::find(band_reads.begin(),band_reads.end(),2)==band_reads.end());
  candles[1].close=200;tick(1500);bool allowed=width2>=20; // BBW1=40/200=.2; BBW2=width2/100
  assert(opens.size()==(allowed ? 1:0) && reentry_state==NONE);
  if(allowed)assert(opens[0].side==side && opens[0].mid==200 && opens[0].atr==2);
  assert(band_reads==std::vector<int>({1,1,2}));tick(1501);tick(1800);assert(opens.size()==(allowed ? 1:0));
 }
 for(int failure=0;failure<7;failure++){
  reset();bbw_mid2=100;bbw_upper2=120;bbw_lower2=80;bbw_bands2_ready=true;
  candles[1].close=179;tick(1200);candles[1].close=200;
  if(failure==0)bbw_bands2_ready=false;
  if(failure==1)bbw_mid2=0;if(failure==2)bbw_mid2=-1;if(failure==3)bbw_mid2=NAN;
  if(failure==4)bbw_upper2=INFINITY;if(failure==5)bbw_lower2=121;
  if(failure==6)bbw_upper2=EMPTY_VALUE;
  tick(1500);assert(opens.empty() && reentry_state==NONE);
  bbw_mid2=100;bbw_upper2=120;bbw_lower2=80;bbw_bands2_ready=true;tick(1501);tick(1800);assert(opens.empty());
 }
 assert(!ValidBBWInputs(0,220,180) && !ValidBBWInputs(NAN,220,180) && !ValidBBWInputs(200,179,180));
 // Tiny increase must not disappear through rounding.
 reset();bbw_mid2=100;bbw_upper2=110;bbw_lower2=90.000000000001;
 candles[1].close=179;tick(1200);candles[1].close=200;tick(1500);assert(opens.empty());
 reset();InpReentryBBWFilter=false;bbw_bands2_ready=false;candles[1].close=179;tick(1200);candles[1].close=200;tick(1500);
 assert(opens.size()==1 && band_reads==std::vector<int>({1,1}));
 reset();InpReentryBBWFilter=true;state=ACTIVE_IDEA;own_positions=1;target=200;g_sl=50;tick(1200);
 assert(state==ACTIVE_IDEA && std::find(band_reads.begin(),band_reads.end(),2)==band_reads.end());
 InpReentryBBWFilter=false;bbw_bands2_ready=true;
 std::cout<<"PASS: BBW decrease/equality/increase both sides, own candle SMA, closed shifts only, no rounding, missing/invalid data consumed, disabled/management regression\n";

 for(bool bbw_pass:{false,true})for(bool adx_pass:{false,true})for(bool macd_pass:{false,true}){
  reset();InpReentryBBWFilter=true;InpReentryMACDConfirm=true;InpReentryADXMode=ADX_BELOW_25;
  bbw_mid2=100;bbw_upper2=bbw_pass ? 120:105;bbw_lower2=80; // .4 or .25: fix failing case below
  if(!bbw_pass)bbw_lower2=95; // .1 < .2, increasing width rejects
  adx_values[1]=adx_pass ? 19:25;
  macd_values[0][1]=macd_pass ? -1:1;macd_values[1][1]=0;macd_values[0][2]=-2;macd_values[1][2]=0;
  candles[1].close=179;tick(1200);candles[1].close=200;tick(1500);
  assert(opens.size()==(bbw_pass && adx_pass && macd_pass ? 1:0));
 }
 InpReentryBBWFilter=false;InpReentryMACDConfirm=false;InpReentryADXMode=ADX_OFF;
 std::cout<<"PASS: BBW/ADX/MACD require AND in the same reentry\n";

 InpStrategy=BB_REENTRY;InpReentryBBWFilter=true;InpReentryBBWMode=BBW_BELOW_P70;bbw_history=true;
 for(int side:{1,-1})for(int low_count:{69,70,100}){
  reset();for(int shift=2;shift<=101;shift++){
   history_mid[shift]=low_count==100 ? 100:100+shift; // A different SMA for each reference candle.
   double value=low_count==100 ? .2:(((shift-2)*37%100)<low_count ? .1:.3);
   history_lower[shift]=0;history_upper[shift]=value*history_mid[shift];history_ready[shift]=true;
  }
  candles[1].close=side==1 ? 179:221;tick(40000);assert(band_reads==std::vector<int>({1}));
  candles[1].close=200;tick(40300);bool allowed=low_count==69;
  assert(opens.size()==(allowed ? 1:0) && reentry_state==NONE);
  assert(band_reads.size()==102 && band_reads[0]==1 && band_reads[1]==1);
  for(int shift=2;shift<=101;shift++)assert(band_reads[shift]==shift);
  tick(40301);tick(40600);assert(opens.size()==(allowed ? 1:0));
 }
 for(int bad_shift:{2,51,101})for(int failure=0;failure<6;failure++){
  reset();for(int shift=2;shift<=101;shift++){history_mid[shift]=100;history_lower[shift]=0;history_upper[shift]=40;history_ready[shift]=true;}
  candles[1].close=179;tick(40000);candles[1].close=200;
  if(failure==0)history_ready[bad_shift]=false;if(failure==1)history_mid[bad_shift]=0;
  if(failure==2)history_mid[bad_shift]=NAN;if(failure==3)history_upper[bad_shift]=INFINITY;
  if(failure==4)history_lower[bad_shift]=41;if(failure==5)history_upper[bad_shift]=EMPTY_VALUE;
  tick(40300);assert(opens.empty() && reentry_state==NONE);
  history_ready[bad_shift]=true;history_mid[bad_shift]=100;history_lower[bad_shift]=0;history_upper[bad_shift]=40;
  tick(40301);tick(40600);assert(opens.empty());
 }
 reset();InpReentryBBWFilter=false;candles[1].close=179;tick(40000);candles[1].close=200;tick(40300);
 assert(opens.size()==1 && band_reads==std::vector<int>({1,1})); // P70 mode is inert when disabled.
 InpReentryBBWMode=BBW_NON_INCREASING;bbw_history=false;
 std::cout<<"PASS: V5C nearest rank index69, excludes signal/shift0, exact references2..101, own SMA, equality rejects, no accumulated V5A, missing/invalid history consumes, disabled regression\n";

 InpStrategy=BB_REENTRY;InpReentryExitMode=EXIT_ATR_FIXED_2;
 reset();state=ACTIVE_IDEA;own_positions=1;g_sl=50;target=130;tp_bar=900;
 closed_mid=205;atr_closed=7;tick(1200);assert(target==130 && g_sl==50 && band_reads.empty());
 closed_mid=199;atr_closed=3;tick(1500);assert(target==130 && g_sl==50 && band_reads.empty());
 profit=-63;tick(1501);assert(state==CLOSING_IDEA && close_calls==1);
 reset();InpReentryExitMode=EXIT_SMA20_DYNAMIC;state=ACTIVE_IDEA;own_positions=1;g_sl=50;target=130;tp_bar=900;
 tick(1200);assert(target==200 && band_reads==std::vector<int>{1});
 std::cout<<"PASS: S3 OnTick leaves target frozen despite SMA/ATR changes, no target reads, money close still active, dynamic regression\n";
}

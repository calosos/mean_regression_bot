// Deterministic regression scenarios; production functions are injected from the current EA.
void tick(datetime t){now=t;datetime bar=t/300*300;candles[0].time=bar;candles[1].time=bar-300;OnTick();}
void reset(SignalMode mode=CLOSED_BAR){
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
}

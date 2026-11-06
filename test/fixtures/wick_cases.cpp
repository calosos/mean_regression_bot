void tick(datetime t){now=t;datetime bar=t/300*300;candles[0].time=bar;candles[1].time=bar-300;OnTick();}
void reset(){
 InpStrategy=BB_WICK_REJECTION;InpSignalMode=SignalMode(99);InpReentryWeekendGuard=false;
 InpReentryMACDConfirm=true;InpReentryADXMode=ADX_BELOW_25;InpReentryBBWFilter=true;
 state=WAITING_SIGNAL;g_last_signal_bar=900;processed_buy=processed_sell=0;cooldown_until=0;
 own_positions=own_orders=0;manual_required=false;history_ok=true;foreign=false;pending.clear();opens.clear();
 rates_ready=series_ready=closed_bands_ready=tp_bands_ready=atr_ready=true;
 band_reads.clear();rate_reads.clear();atr_reads.clear();stoch_reads.clear();macd_reads.clear();adx_reads.clear();event_tags.clear();
 closed_mid=200;atr_closed=2;InpWickMinRatio=.4;g_sl=0;target=200;reentry_state=NONE;
 candles[1]={900,170,195,185,180};
}
int main(){
 reset();tick(1203);assert(opens.size()==1 && opens[0].side==1 && opens[0].mid==200 && opens[0].atr==2);
 assert(band_reads==std::vector<int>{1} && atr_reads==std::vector<int>{1} && rate_reads==std::vector<int>{1});
 assert(macd_reads.empty() && adx_reads.empty() && stoch_reads.empty());tick(1204);assert(opens.size()==1);
 reset();candles[1]={900,205,230,215,220};tick(1200);assert(opens.size()==1 && opens[0].side==-1);
 reset();candles[1]={900,205,230,215,210};tick(1200);assert(opens.size()==1); // bullish sell
 reset();candles[1].open=179.999;tick(1200);assert(opens.empty());
 reset();candles[1].close=180;tick(1200);assert(opens.empty());
 reset();candles[1]={900,169,194,185,179};tick(1200);assert(opens.size()==1); // Open below lower band
 reset();candles[1]={900,170,195,183,185};tick(1200);assert(opens.size()==1); // bearish buy
 reset();candles[1].open=185;tick(1200);assert(opens.size()==1); // doji
 reset();candles[1]={900,170,230,200,200};tick(1200);assert(opens.empty());assert(std::find(event_tags.begin(),event_tags.end(),"AMBIGUOUS_SIGNAL")!=event_tags.end());
 for(int invalid=0;invalid<5;invalid++){
  reset();if(invalid==0)candles[1].high=candles[1].low;if(invalid==1)candles[1].open=NAN;
  if(invalid==2)candles[1].low=-1;if(invalid==3)candles[1].high=INFINITY;if(invalid==4)candles[1].open=200;
  tick(1200);assert(opens.empty());
 }
 reset();tick(1000);assert(opens.empty()); // init does not process historical close
 reset();now=1201;candles[0].time=1200;candles[1].time=600;OnTick();assert(opens.empty());tick(1202);assert(opens.empty());
 for(int missing=0;missing<4;missing++){
  reset();if(missing==0)rates_ready=false;if(missing==1)closed_bands_ready=false;if(missing==2)atr_ready=false;if(missing==3)series_ready=false;
  tick(1200);assert(opens.empty());rates_ready=series_ready=closed_bands_ready=atr_ready=true;tick(1201);assert(opens.empty());
 }
 for(int blocked=0;blocked<3;blocked++){
  reset();if(blocked==0){state=ACTIVE_IDEA;own_positions=1;}if(blocked==1){state=COOLDOWN;cooldown_until=1201;}if(blocked==2)foreign=true;
  tick(1200);state=WAITING_SIGNAL;own_positions=0;foreign=false;tick(1201);assert(opens.empty());
 }
 std::cout<<"PASS: wick exact40%, smaller ratio, band equality, Open outside, both colors/doji, no preparation, ambiguous, invalid OHLC, closed snapshots, no replay/duplicates/late data/blocked opportunities\n";
}

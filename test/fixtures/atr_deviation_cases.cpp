void tick(datetime t){now=t;datetime bar=t/300*300;candles[0].time=bar;candles[1].time=bar-300;OnTick();}
void reset(){
 InpStrategy=ATR_DEVIATION_REENTRY;InpATRDeviationThreshold=1.5;InpSignalMode=SignalMode(99);InpReentryWeekendGuard=false;
 InpReentryMACDConfirm=true;InpReentryADXMode=ADX_BELOW_25;InpReentryBBWFilter=true;
 state=WAITING_SIGNAL;g_last_signal_bar=900;processed_buy=processed_sell=0;cooldown_until=0;
 reentry_state=NONE;reentry_outer_bar=0;own_positions=own_orders=0;manual_required=false;history_ok=true;foreign=false;
 pending.clear();opens.clear();event_tags.clear();band_reads.clear();rate_reads.clear();atr_reads.clear();stoch_reads.clear();macd_reads.clear();adx_reads.clear();
 rates_ready=series_ready=closed_bands_ready=atr_ready=true;closed_mid=200;atr_closed=2;g_sl=0;target=200;
 candles[1]={900,170,230,196,180};
}
int main(){
 for(int side:{1,-1}){
  reset();candles[1].close=200-side*4;tick(1203);assert(opens.empty() && reentry_state==(side==1 ? WAIT_BUY_REENTRY:WAIT_SELL_REENTRY));
  assert(reentry_outer_bar==900 && deviation_prep_close==200-side*4 && deviation_prep_d==-side*2);
  candles[1].close=200-side*5;tick(1500);assert(reentry_outer_bar==900 && deviation_prep_close==200-side*4 && opens.empty());
  candles[1].close=200-side*3;tick(1800);assert(opens.empty() && reentry_state!=NONE); // equality T
  candles[1].close=200-side*2;tick(2105);assert(opens.size()==1 && opens[0].side==side && opens[0].atr==2 && opens[0].mid==200 && reentry_state==NONE);
  tick(2106);tick(2400);assert(opens.size()==1);
  assert(band_reads.empty() && stoch_reads.empty() && macd_reads.empty() && adx_reads.empty());
  for(int shift:atr_reads)assert(shift==1);for(int shift:rate_reads)assert(shift==1);
 }
 for(double d:{-1.5,1.5}){reset();candles[1].close=200+d*2;tick(1200);assert(reentry_state==NONE && opens.empty());}
 for(int side:{1,-1})for(double d:{0.,.5,-.5}){
  reset();candles[1].close=200-side*4;tick(1200);candles[1].close=200+d*2;tick(1500);
  if(d==0 || d*side>0)assert(reentry_state==NONE && opens.empty());
 }
 reset();tick(1200);candles[1].close=204;tick(1500);assert(reentry_state==WAIT_SELL_REENTRY && reentry_outer_bar==1200);
 candles[1].close=201;tick(1800);assert(opens.size()==1 && opens[0].side==-1);
 // ATR growth alone reduces normalized deviation; price does not need to return.
 reset();tick(1200);atr_closed=4;tick(1500);assert(opens.size()==1 && opens[0].side==1 && opens[0].atr==4);
 for(int invalid=0;invalid<7;invalid++){
  reset();tick(1200);
  if(invalid==0)closed_bands_ready=false;if(invalid==1)atr_ready=false;if(invalid==2)rates_ready=false;
  if(invalid==3)atr_closed=0;if(invalid==4)candles[1].close=NAN;if(invalid==5)closed_mid=NAN;
  if(invalid==6){now=1501;candles[0].time=1500;candles[1].time=900;OnTick();}else tick(1500);
  assert(reentry_state==NONE && opens.empty());closed_bands_ready=atr_ready=rates_ready=true;closed_mid=200;atr_closed=2;candles[1].close=198;
  tick(1502);tick(1800);assert(opens.empty());
 }
 reset();tick(1200);candles[1].close=198;tick(2100);assert(reentry_state==NONE && opens.empty()); // skipped M5 opportunity
 for(int blocked=0;blocked<3;blocked++){
  reset();tick(1200);if(blocked==0){state=ACTIVE_IDEA;own_positions=1;}if(blocked==1){state=COOLDOWN;cooldown_until=1501;}if(blocked==2)foreign=true;
  tick(1500);assert(reentry_state==NONE);state=WAITING_SIGNAL;own_positions=0;foreign=false;candles[1].close=198;tick(1502);tick(1800);assert(opens.empty());
 }
 reset();tick(1000);assert(opens.empty() && reentry_state==NONE);
 // SMA TP updates have no Bollinger dependency and leave SL unchanged.
 reset();state=ACTIVE_IDEA;own_positions=1;g_sl=50;tp_bar=900;closed_mid=205;tick(1200);assert(target==205 && g_sl==50 && band_reads.empty());
 closed_mid=199;tick(1500);assert(target==199 && g_sl==50 && band_reads.empty());
 std::cout<<"PASS: ATR deviation transitions/dedup/thresholds/mean/opposite, first snapshot preserved, ATR-only return, closed same-candle inputs, no filters/Bollinger, invalid/gap/blocked cleanup and SMA TP\n";
}

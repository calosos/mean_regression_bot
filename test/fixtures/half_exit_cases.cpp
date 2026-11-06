void tick(datetime stamp){now=stamp;candles[0].time=stamp/300*300;candles[1].time=candles[0].time-300;OnTick();}
int main(){
 for(int side:{1,-1}){
  InpStrategy=BB_REENTRY;InpReentryExitMode=EXIT_HALF_SMA20_DYNAMIC;InpReentryWeekendGuard=false;
  state=ACTIVE_IDEA;own_positions=1;direction=side;g_sl=side==1 ? 50:150;profit=0;tp_bar=900;g_last_signal_bar=900;
  pending.clear();entry_price=side==1 ? 90:110;double e1=entry_price,sl=g_sl;
  closed_mid=side==1 ? 120:90;target=200;band_reads.clear();close_calls=0;
  tick(1203);assert(state==ACTIVE_IDEA && target==(side==1 ? 105:100) && g_sl==sl && entry_price==e1);
  assert(band_reads==std::vector<int>{1});
  closed_mid=side==1 ? 130:80;tick(1500);assert(target==(side==1 ? 110:95) && entry_price==e1 && g_sl==sl);
  closed_mid=side==1 ? 108:92;tick(1800);assert(state==CLOSING_IDEA && close_calls==1 && g_sl==sl && entry_price==e1);
  assert(band_reads==std::vector<int>({1,1,1}));
 }
 std::cout<<"PASS: real OnTick/Target: half SMA updates only from shift1, anchors fixed E1 rather than current quote, preserves SL, closes immediately when updated target reached\n";

 for(int side:{1,-1}){
  InpStrategy=BB_REENTRY;InpReentryExitMode=EXIT_OPPOSITE_BAND_DYNAMIC;state=ACTIVE_IDEA;own_positions=1;
  direction=side;g_sl=side==1 ? 50:150;profit=0;tp_bar=900;g_last_signal_bar=900;entry_price=123;
  closed_mid=100;closed_upper=110;closed_lower=90;target=200;band_reads.clear();close_calls=0;
  tick(1203);assert(state==ACTIVE_IDEA && target==(side==1 ? 110:90));
  closed_upper=115;closed_lower=85;tick(1500);assert(state==ACTIVE_IDEA && target==(side==1 ? 115:85));
  closed_upper=108;closed_lower=92;tick(1800);assert(state==ACTIVE_IDEA && target==(side==1 ? 108:92));
  closed_upper=side==1 ? 99:110;closed_lower=side==1 ? 90:101;closed_mid=side==1 ? 95:105;tick(2100);assert(state==CLOSING_IDEA && close_calls==1);
  assert(band_reads==std::vector<int>({1,1,1,1}) && g_sl==(side==1 ? 50:150));
 }
 std::cout<<"PASS: opposite-band real Target/OnTick uses closed shift1, moves target both ways, ignores SMA, closes reached objective without touching SL\n";
}

void tick(datetime stamp){now=stamp;candles[0].time=stamp/300*300;candles[1].time=candles[0].time-300;OnTick();}
int main(){
 InpStrategy=BB_REENTRY;InpReentryExitMode=EXIT_HALF_SMA20_TRAIL_ATR;InpReentryWeekendGuard=false;
 state=ACTIVE_IDEA;own_positions=1;direction=1;g_sl=50;profit=0;tp_bar=900;g_last_signal_bar=900;
 closed_mid=99;target=150;close_calls=0;tick(1203);
 assert(state==ACTIVE_IDEA && target==99 && partial_step_calls==1 && close_calls==0); // no full TP close
 g_half.trailing=true;closed_mid=120;band_reads.clear();tick(1500);
 assert(state==ACTIVE_IDEA && target==99 && band_reads.empty() && partial_step_calls==2);
 profit=-63;tick(1501);assert(state==CLOSING_IDEA && close_calls==1); // money exit still priority
 std::cout<<"PASS: real OnTick routes reached SMA to partial, stops SMA updates during trailing, retains monetary closure\n";
}

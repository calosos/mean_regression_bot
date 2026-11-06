int main(){
 reset_init();assert(OnInit()==INIT_SUCCEEDED && stoch_created==1 && rsi_created==0 && bands_created==1 && atr_created==1);
 reset_init();InpOscillator=RSI;InpStochasticK=0;assert(OnInit()==INIT_SUCCEEDED && rsi_created==1 && stoch_created==0);
 for(int period:{0,-1}){reset_init();InpOscillator=RSI;InpRSIPeriod=period;assert(OnInit()==INIT_PARAMETERS_INCORRECT && bands_created==0);}
 for(auto levels:std::vector<std::pair<double,double>>{{0,70},{30,100},{70,30},{30,30},{NAN,70},{30,INFINITY}}){
  reset_init();InpOscillator=RSI;InpRSIBuyLevel=levels.first;InpRSISellLevel=levels.second;assert(OnInit()==INIT_PARAMETERS_INCORRECT && rsi_created==0);
 }
 reset_init();InpRSIPeriod=0;InpRSIBuyLevel=NAN;assert(OnInit()==INIT_SUCCEEDED && stoch_created==1);
 reset_init();InpStrategy=BB_REENTRY;InpSignalMode=SignalMode(99);InpOscillator=Oscillator(99);InpStochasticK=0;InpRSIPeriod=0;
 InpRSIBuyLevel=NAN;InpBollingerPeriod=0;InpBollingerDeviation=NAN;InpATRPeriod=0;InpATRMax=NAN;InpTPFactor=NAN;
 assert(OnInit()==INIT_SUCCEEDED && rsi_created==0 && stoch_created==0 && oscillator_handle==INVALID_HANDLE);
 assert(bb_period==20 && bb_deviation==2.5 && atr_period==14 && bands_created==1 && atr_created==1);
 assert(reentry_state==NONE && reentry_outer_bar==0 && g_last_signal_bar==1200);
 reset_init();InpStrategy=BB_REENTRY;InpRiskBaseUSD=0;assert(OnInit()==INIT_PARAMETERS_INCORRECT && bands_created==0);
 reset_init();tester=false;assert(OnInit()==INIT_FAILED && bands_created==0);
 reset_init();currency="EUR";assert(OnInit()==INIT_PARAMETERS_INCORRECT && bands_created==0);
 std::cout<<"PASS: actual OnInit: selected indicators/parameters only, BB fixed settings, no oscillator, empty preparation and tester/USD guards\n";

 for(double multiplier:{0.,-1.,double(NAN),double(INFINITY)}){
  reset_init();InpStrategy=BB_REENTRY;InpReentrySLATR=multiplier;
  assert(OnInit()==INIT_PARAMETERS_INCORRECT && bands_created==0);
  reset_init();InpStrategy=ORIGINAL;InpReentrySLATR=multiplier;
  assert(OnInit()==INIT_SUCCEEDED && stoch_created==1);
 }
 for(double multiplier:{2.,3.,.5}){
  reset_init();InpStrategy=BB_REENTRY;InpReentrySLATR=multiplier;assert(OnInit()==INIT_SUCCEEDED);
 }
 std::cout<<"PASS: BB SL ATR multiplier positive/finite validation; ORIGINAL ignores it\n";

 for(auto margins:std::vector<std::pair<int,int>>{{60,30},{30,30},{1,1}}){
  reset_init();InpStrategy=BB_REENTRY;InpReentryWeekendGuard=true;InpWeekendEntryBlockMinutes=margins.first;InpWeekendCloseMinutes=margins.second;
  assert(OnInit()==INIT_SUCCEEDED);
 }
 for(auto margins:std::vector<std::pair<int,int>>{{29,30},{60,0},{-1,1},{0,-1}}){
  reset_init();InpStrategy=BB_REENTRY;InpReentryWeekendGuard=true;InpWeekendEntryBlockMinutes=margins.first;InpWeekendCloseMinutes=margins.second;
  assert(OnInit()==INIT_PARAMETERS_INCORRECT && bands_created==0);
  InpReentryWeekendGuard=false;assert(OnInit()==INIT_SUCCEEDED);
  reset_init();InpStrategy=ORIGINAL;InpReentryWeekendGuard=true;InpWeekendEntryBlockMinutes=margins.first;InpWeekendCloseMinutes=margins.second;
  assert(OnInit()==INIT_SUCCEEDED);
 }
 std::cout<<"PASS: weekend margins validated only for BB_REENTRY with guard enabled\n";

 InpReentryWeekendGuard=false;
 for(int bad=0;bad<4;bad++){
  reset_init();InpStrategy=BB_REENTRY;InpReentryMACDConfirm=true;InpMACDFast=12;InpMACDSlow=26;InpMACDSignal=9;macd_created=0;
  if(bad==0)InpMACDFast=0;if(bad==1)InpMACDSlow=-1;if(bad==2)InpMACDSignal=0;if(bad==3)InpMACDFast=InpMACDSlow;
  assert(OnInit()==INIT_PARAMETERS_INCORRECT && macd_created==0);
  InpReentryMACDConfirm=false;assert(OnInit()==INIT_SUCCEEDED && macd_created==0);
  InpStrategy=ORIGINAL;InpReentryMACDConfirm=true;assert(OnInit()==INIT_SUCCEEDED && macd_created==0);
 }
 reset_init();InpStrategy=BB_REENTRY;InpReentryMACDConfirm=true;InpMACDFast=12;InpMACDSlow=26;InpMACDSignal=9;macd_created=0;
 assert(OnInit()==INIT_SUCCEEDED && macd_created==1 && macd_handle==77);
 std::cout<<"PASS: MACD periods validated and handle created only for enabled BB confirmation\n";

 for(auto mode:{ADX_OFF,ADX_BELOW_25,ADX_BELOW_20,ADX_BELOW_25_FALLING}){
  reset_init();InpStrategy=BB_REENTRY;InpReentryADXMode=mode;adx_created=0;adx_handle=INVALID_HANDLE;
  assert(OnInit()==INIT_SUCCEEDED && adx_created==(mode==ADX_OFF ? 0:1));
  if(mode==ADX_OFF)assert(adx_handle==INVALID_HANDLE);else assert(adx_handle==88);
  reset_init();InpStrategy=ORIGINAL;adx_created=0;assert(OnInit()==INIT_SUCCEEDED && adx_created==0);
 }
 reset_init();InpStrategy=BB_REENTRY;InpReentryADXMode=ReentryADXMode(99);assert(OnInit()==INIT_PARAMETERS_INCORRECT);
 InpStrategy=ORIGINAL;assert(OnInit()==INIT_SUCCEEDED);InpReentryADXMode=ADX_OFF;
 std::cout<<"PASS: ADX handle only for active BB modes; invalid mode rejected only for BB\n";

 reset_init();InpStrategy=BB_REENTRY;InpReentryBBWFilter=true;InpReentryBBWMode=BBW_BELOW_P70;assert(OnInit()==INIT_SUCCEEDED);
 InpReentryBBWMode=ReentryBBWMode(99);assert(OnInit()==INIT_PARAMETERS_INCORRECT);
 InpReentryBBWFilter=false;assert(OnInit()==INIT_SUCCEEDED);
 InpStrategy=ORIGINAL;InpReentryBBWFilter=true;assert(OnInit()==INIT_SUCCEEDED);
 std::cout<<"PASS: BBW mode validation only for enabled BB filter\n";

 reset_init();InpStrategy=BB_WICK_REJECTION;InpReentryMACDConfirm=true;InpMACDFast=0;InpSignalMode=SignalMode(99);
 InpReentryADXMode=ReentryADXMode(99);InpReentryBBWFilter=true;InpReentryBBWMode=ReentryBBWMode(99);InpOscillator=Oscillator(99);
 rsi_created=stoch_created=macd_created=adx_created=0;
 assert(OnInit()==INIT_SUCCEEDED && rsi_created==0 && stoch_created==0 && macd_created==0 && adx_created==0);
 assert(bb_period==20 && bb_deviation==2.5 && atr_period==14);
 for(double bad:{0.,-1.,1.01,double(NAN),double(INFINITY)}){InpWickMinRatio=bad;assert(OnInit()==INIT_PARAMETERS_INCORRECT);}
 InpWickMinRatio=1;assert(OnInit()==INIT_SUCCEEDED);
 InpReentrySLATR=0;assert(OnInit()==INIT_PARAMETERS_INCORRECT);
 std::cout<<"PASS: V6 parameters validated, unselected filters ignored, Bollinger/ATR only\n";

 reset_init();InpStrategy=ATR_DEVIATION_REENTRY;InpReentrySLATR=2;InpATRMax=8;
 InpWickMinRatio=NAN;InpMACDFast=0;InpReentryMACDConfirm=true;InpReentryBBWFilter=true;InpReentryADXMode=ReentryADXMode(99);
 bands_created=sma_created=rsi_created=stoch_created=macd_created=adx_created=0;
 assert(OnInit()==INIT_SUCCEEDED && sma_created==1 && bands_created==0 && atr_period==14);
 assert(rsi_created==0 && stoch_created==0 && macd_created==0 && adx_created==0);
 for(double t:{1.5,2.,2.5,3.}){InpATRDeviationThreshold=t;assert(OnInit()==INIT_SUCCEEDED);}
 for(double t:{0.,-1.,double(NAN),double(INFINITY)}){InpATRDeviationThreshold=t;assert(OnInit()==INIT_PARAMETERS_INCORRECT);}
 std::cout<<"PASS: ATR deviation iMA20/ATR14 only, threshold validation, ignored filters\n";

 reset_init();InpStrategy=BB_REENTRY;InpReentryExitMode=EXIT_ATR_FIXED_2;InpReentryMACDConfirm=false;InpReentryBBWFilter=false;InpReentryADXMode=ADX_OFF;InpReentrySLATR=2;
 assert(OnInit()==INIT_SUCCEEDED);InpReentryExitMode=ReentryExitMode(99);assert(OnInit()==INIT_PARAMETERS_INCORRECT);
 reset_init();InpStrategy=ATR_DEVIATION_REENTRY;InpReentryExitMode=ReentryExitMode(99);InpATRDeviationThreshold=1.5;assert(OnInit()==INIT_SUCCEEDED);
 std::cout<<"PASS: exit selector validated only for BB_REENTRY\n";

 reset_init();InpStrategy=BB_REENTRY;InpReentryExitMode=EXIT_HALF_SMA20_DYNAMIC;
 InpReentryMACDConfirm=InpReentryBBWFilter=false;InpReentryADXMode=ADX_OFF;assert(OnInit()==INIT_SUCCEEDED);
 std::cout<<"PASS: half SMA exit mode initializes\n";

 reset_init();InpStrategy=BB_REENTRY;InpReentryExitMode=EXIT_OPPOSITE_BAND_DYNAMIC;
 InpReentryMACDConfirm=InpReentryBBWFilter=false;InpReentryADXMode=ADX_OFF;assert(OnInit()==INIT_SUCCEEDED);
 std::cout<<"PASS: opposite-band exit initializes\n";

 reset_init();InpStrategy=BB_REENTRY;InpReentryExitMode=EXIT_HALF_SMA20_TRAIL_ATR;
 InpReentryMACDConfirm=InpReentryBBWFilter=false;InpReentryADXMode=ADX_OFF;assert(OnInit()==INIT_SUCCEEDED);
 std::cout<<"PASS: scale-out/trailing exit selector initializes\n";
}

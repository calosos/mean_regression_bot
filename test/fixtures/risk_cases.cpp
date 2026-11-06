// Deterministic regression scenarios; production functions are injected from the current EA.
int main() {
 int checked=0;
 assert(Budget()==62.5);
 assert(SignalSide(90,111,90,110,9,300)==1);
 assert(SignalSide(89,110,90,110,91,300)==-1);
 assert(SignalSide(90,110,90,110,10,300)==0);
 assert(SignalSide(90,110,90,110,90,300)==0);
 processed_buy=300; assert(SignalSide(89,110,90,110,9,300)==0);
 assert(SignalSide(89,110,90,110,9,600)==1); processed_buy=0;
 assert(ATRAllowed(8) && !ATRAllowed(8.0001) && !ATRAllowed(0) && !ATRAllowed(-1));
 double v=0,r=0;
 assert(Size(2500,v) && SamePrice(v,.06));
 InpRiskBaseUSD=10000; frozen_atr=6; assert(!Size(2500,v));
 fail_profit=true; assert(!Size(2500,v)); fail_profit=false;
 for(int side : {-1,1}) for(double base : {10000.,25000.,50000.})
 for(double tick : {.01,.05,.1}) for(int a=1;a<=800;a++) {
  direction=side; InpRiskBaseUSD=base; tick_size=tick; frozen_atr=a*.01;
  double e1=2500.013,e2,sl; Levels(e1,e2,sl);
  if(Size(e1,v)) {
   assert(v>=volume_min && v<=volume_max);
   assert(Risk(v,e1,e2,sl,r) && r<=Budget());
   double higher=NormalizeDouble(v+volume_step,8),next=0;
   if(higher<=volume_max) assert(Risk(higher,e1,e2,sl,next) && next>Budget());
   checked++;
  }
 }
 tick_size=.01; direction=1; assert(SamePrice(Target(100,110,90),99));
 target=99; assert(HitTarget(MqlTick{99,99.2})); assert(!HitTarget(MqlTick{98.9,99.1}));
 direction=-1; assert(SamePrice(Target(100,110,90),101));
 target=101; assert(HitTarget(MqlTick{100.8,101})); assert(!HitTarget(MqlTick{100.9,101.1}));
 for(datetime t=0;t<86400;t++) { Cooldown(t); assert(cooldown_until==t-t%300+600); assert(state==COOLDOWN); }
 std::cout<<"PASS: "<<checked<<" lot/risk combinations; 86400 cooldown times; signal, ATR, TP and calculation failure boundaries\n";

 double result=123;
 for(int count:{-1,0,2}){copied=count;assert(!Value(10,0,1,result) && result==123);}
 copied=1;
 for(double bad:{EMPTY_VALUE,double(NAN),double(INFINITY)}){indicator_value=bad;assert(!Value(10,0,1,result) && result==123);}
 indicator_value=29;assert(Value(10,0,1,result) && result==29);
 std::cout<<"PASS: actual CopyBuffer reader rejects missing/invalid/EMPTY_VALUE without replacing output\n";

 InpStrategy=BB_REENTRY;InpRiskBaseUSD=25000;tick_size=.01;direction=1;frozen_atr=2;
 assert(Size(2500,v) && SamePrice(v,.10));
 double e2,sl;Levels(2500,e2,sl);assert(e2==0 && sl==2494);
 assert(Risk(v,2500,e2,sl,r) && SamePrice(r,60));
 assert(SamePrice(Target(2501.234,9999,1),2501.23));
 InpATRMax=100;assert(!ATRAllowed(8.01) && ATRAllowed(8));
 fail_profit=true;assert(!Size(2500,v));fail_profit=false;
 InpRiskBaseUSD=1000;frozen_atr=8;assert(!Size(2500,v));
 int single_checked=0;
 for(double multiplier:{2.,3.})for(int side:{-1,1})for(double base:{10000.,25000.,50000.})for(double tick:{.01,.05,.1})for(int a=1;a<=800;a++){
  InpReentrySLATR=multiplier;direction=side;InpRiskBaseUSD=base;tick_size=tick;frozen_atr=a*.01;
  double e1=2500.013;Levels(e1,e2,sl);assert(e2==0);
  if(Size(e1,v)){
   assert(Risk(v,e1,e2,sl,r) && r<=Budget());
   double higher=NormalizeDouble(v+volume_step,8),next=0;
   if(higher<=volume_max)assert(Risk(higher,e1,e2,sl,next) && next>Budget());
   single_checked++;
  }
 }
 std::cout<<"PASS: "<<single_checked<<" BB single-entry risk/rounding combinations, 3 ATR lot, fixed ATR cap, SMA target and calculation/min-volume rejection\n";
}

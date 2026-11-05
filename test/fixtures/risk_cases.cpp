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
}

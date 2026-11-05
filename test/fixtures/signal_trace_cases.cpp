// Deterministic regression scenarios; production functions are injected from the current EA.
int main(){
 MqlRates candle={0,98.12345,105.12345,95.12345,100.12345};
 const char *evaluations[]={"2026.07.06 01:00:02","2026.07.22 01:00:00","2026.10.27 01:00:00"};
 const char *bars[]={"2026.07.03 19:55:00","2026.07.21 23:55:00","2026.10.26 23:55:00"};
 long elapsed[]={190802,3600,3600};
 for(int i=0;i<3;i++){
  now=parse(evaluations[i]);candle.time=parse(bars[i]);logs.clear();quote_reads=0;
  SignalLog(1,candle,100.555,110.666,90.444,9.111,2.222);
  assert(logs.size()==1 && quote_reads==1);
  auto text=logs[0];
  for(auto key:{"modo=CLOSED_BAR","Open=98.12345","High=105.12345","Low=95.12345","Close=100.12345","LowerBand=90.4440000000","SMA20=100.5550000000","UpperBand=110.6660000000","K=9.1110000000","ATR=2.2220000000","cierre_dentro_bandas=true","mercado_bid=500.00000","mercado_ask=501.00000","mercado_referencia_e1=501.00000"})assert(text.find(key)!=string::npos);
  assert(text.find(string("evaluacion=")+evaluations[i])!=string::npos);
  assert(text.find(string("vela=")+bars[i])!=string::npos);
  assert(text.find("segundos_desde_cierre="+std::to_string(elapsed[i]))!=string::npos);
  assert(text.find("cierre_nominal="+TimeToString(candle.time+300,3))!=string::npos);
 }
 logs.clear();SignalLog(-1,candle,100.555,110.666,90.444,91.111,2.222);assert(logs[0].find("mercado_referencia_e1=500.00000")!=string::npos);
 quote_ok=false;logs.clear();SignalLog(1,candle,100.555,110.666,90.444,9.111,2.222);assert(logs.size()==1 && logs[0].find("mercado_disponible=false")!=string::npos && logs[0].find("mercado_bid")==string::npos);
 quote_ok=true;candle.close=90.444;logs.clear();SignalLog(1,candle,100.555,110.666,90.444,9.111,2.222);assert(logs[0].find("cierre_dentro_bandas=false")!=string::npos);
 detailed=false;logs.clear();SignalLog(1,candle,100.555,110.666,90.444,9.111,2.222);assert(logs.empty());
 detailed=true;InpSignalMode=INTRABAR;logs.clear();quote_reads=0;SignalLog(1,candle,100.555,110.666,90.444,9.111,2.222);assert(logs.size()==1 && quote_reads==0 && logs[0].find("modo=INTRABAR")!=string::npos && logs[0].find("evaluacion=")==string::npos);
 std::cout<<"PASS: actual log function with synthetic OHLC snapshots; all fields, 190802/3600/3600 second ages, distinct Bid/Ask vs Close, missing quote nonfatal, bool boundary, detailed-log toggle and unchanged intrabar output\n";
}

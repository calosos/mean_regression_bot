int main(){
 now=1203;EvaluateWickSignal();assert(opened==1 && logs.size()==1);
 for(auto key:{"estrategia=BB_WICK_REJECTION","evaluacion=","vela=","direccion=BUY","Open=180.0000000000","High=195.0000000000","Low=170.0000000000","Close=185.0000000000","LowerBand=180.0000000000","SMA20=200.0000000000","UpperBand=220.0000000000","ATR=2.0000000000","rango=25","cuerpo=5","mecha_inferior=10","mecha_superior=10","ratio_inferior=0.4","ratio_superior=0.4","cuerpo_rango=0.2","distancia_cierre_ATR=2.5","mercado_bid=500.0000000000","mercado_ask=501.0000000000","mercado_referencia_e1=501.0000000000"})assert(logs[0].find(key)!=string::npos);
 EvaluateWickSignal();assert(opened==1 && logs.size()==1);
 logs.clear();processed_buy=0;source_candle={900,220,230,205,215};EvaluateWickSignal();assert(opened==2 && logs.size()==1);
 assert(logs[0].find("direccion=SELL")!=string::npos && logs[0].find("mercado_referencia_e1=500.0000000000")!=string::npos);
 assert(logs[0].find("distancia_cierre_ATR=2.5")!=string::npos);
 std::cout<<"PASS: V6 real SIGNAL formatter has exact geometry, ratios, distance, snapshots and separate market reference for both sides\n";
}

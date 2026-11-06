int main(){
 InpStrategy=ATR_DEVIATION_REENTRY;source_candle.close=196;source_candle.time=900;now=1203;g_last_signal_bar=1200;
 EvaluateATRDeviationSignal();assert(reentry_state==WAIT_BUY_REENTRY && opened==0);
 source_candle.time=1200;now=1502;g_last_signal_bar=1500;trace_atr=4;
 EvaluateATRDeviationSignal();assert(reentry_state==NONE && opened==1);
 auto text=logs.back();
 for(auto field:{"estrategia=ATR_DEVIATION_REENTRY","evaluacion=","preparacion=","confirmacion=","Close_preparacion=196","SMA_preparacion=200","ATR_preparacion=2","D_preparacion=-2","Close_confirmacion=196","SMA_confirmacion=200","ATR_confirmacion=4","D_confirmacion=-1","cambio_Close=0","cambio_SMA=0","cambio_ATR=2","mercado_referencia_e1=501.0000000000"})assert(text.find(field)!=string::npos);
 std::cout<<"PASS: ATR deviation real SIGNAL snapshot and deltas record ATR-only normalized return without price movement\n";
}

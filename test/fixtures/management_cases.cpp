// Deterministic regression scenarios; production functions are injected from the current EA.
void fresh() {
 reset(); g_management_retries.clear(); g_request_cycle=1; g_market_retry_after=0;
 now=1000; forced_code=0; modify_calls=0; reconciliations=0; quote_bid=2490; quote_ask=2490.2;
}
int main() {
 fresh(); positions={{1,true},{2,true}}; orders={{3,true},{4,false}}; forced_code=TRADE_RETCODE_MARKET_CLOSED;
 for(int ms=0;ms<60000;ms++) {
  now=1000+ms/1000; g_request_cycle++; PruneManagementRetries();
  CloseStep(); CloseStep();
  assert(state==CLOSING_IDEA && OwnPositions()==2 && OwnOrders()==1 && cooldown_calls==0);
 }
 assert(delete_calls+close_calls==12); assert(reconciliations==120000);
 now=1060; g_request_cycle++; forced_code=0; CloseStep();
 assert(state==COOLDOWN && positions.empty() && orders.size()==1 && !orders[0].own && cooldown_calls==1);
 std::cout<<"PASS: 60000 ticks, duplicate CloseStep calls: 12 market-closed requests/minute, 120000 reconciliations; recovery and foreign order preserved\n";
 fresh(); positions={{1,true}}; forced_code=10016;
 CloseStep(); assert(close_calls==1);
 for(int sec=0;sec<5;sec++) { now=1000+sec; g_request_cycle++; CloseStep(); assert(close_calls==1 && state==CLOSING_IDEA); }
 now=1005; g_request_cycle++; CloseStep(); assert(close_calls==2);
 forced_code=0; now=1010; g_request_cycle++; CloseStep(); assert(state==COOLDOWN);
 std::cout<<"PASS: other definitive rejection waits exactly 5 seconds; no permanent retry limit\n";
 fresh(); positions={{1,true}}; orders={{3,true}}; state=ACTIVE_IDEA; forced_code=10016;
 SyncTP(); assert(modify_calls==2);
 BeginClose("risk"); CloseStep(); assert(close_calls==0 && delete_calls==0 && state==CLOSING_IDEA);
 now=1005; g_request_cycle++; forced_code=0; CloseStep(); assert(state==COOLDOWN);
 std::cout<<"PASS: shared per-object pacing for TP -> close/cancel transition in same cycle\n";
 fresh(); positions={{1,true}}; orders={{3,true}}; state=ACTIVE_IDEA; forced_code=TRADE_RETCODE_MARKET_CLOSED;
 SyncTP(); assert(modify_calls==1);
 // Logical target remains observed even while management requests are paused.
 quote_bid=2500; quote_ask=2500.2; g_request_cycle++; now=1001; SyncTP();
 assert(state==CLOSING_IDEA); CloseStep(); assert(delete_calls==0 && close_calls==0);
 now=1005; g_request_cycle++; forced_code=0; CloseStep(); assert(state==COOLDOWN);
 std::cout<<"PASS: market-closed pause shared across tickets; logical TP triggers closing during wait\n";
 fresh(); positions={{1,true,true}}; orders={{3,true},{4,false}}; forced_code=TRADE_RETCODE_MARKET_CLOSED;
 CloseStep(); assert(manual_required && close_calls==0 && OwnOrders()==1);
 now=1005; g_request_cycle++; forced_code=0; CloseStep();
 assert(OwnOrders()==0 && close_calls==0 && positions.size()==1 && state==CLOSING_IDEA);
 fresh(); positions={{1,true}}; orders={{3,true}}; fill_on_delete=true; CloseStep();
 assert(state==COOLDOWN && positions.empty() && orders.empty());
 fresh(); positions={{1,true}}; pending={1}; CloseStep(); assert(close_calls==0 && cooldown_calls==0);
 pending.clear(); g_request_cycle++; CloseStep(); assert(state==COOLDOWN);
 fresh(); positions={{1,true}}; RememberManagementResult(1,false,TRADE_RETCODE_MARKET_CLOSED);
 CloseStep(); assert(close_calls==0); now=1005; g_request_cycle++; CloseStep(); assert(state==COOLDOWN);
 fresh(); positions={{1,true}};
 assert(ManagementRequestAllowed(1,false)); RememberManagementResult(1,false,TRADE_RETCODE_DONE_PARTIAL);
 assert(!ManagementRequestAllowed(1,false)); g_request_cycle++; assert(ManagementRequestAllowed(1,false));
 fresh(); positions={{1,true}}; assert(ManagementRequestAllowed(1,false)); positions.clear();
 PruneManagementRetries(); assert(g_management_retries.empty());
 std::cout<<"PASS: netting quarantine, E2 fill while closing, pending-request lock, initial SL result pacing, partial close continuation and retry record cleanup\n";
}

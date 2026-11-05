// Monetary excursions are measured on reconciled joint samples, never leg maxima.
const long first_stamp=1000123;
void fresh() {
 now=1000;idea_start=1000;e1_order=100;e2_order=0;state=ACTIVE_IDEA;
 had_exposure=true;netting=false;history_available=true;history_ok=true;
 configured_budget=62.5;position_ids.clear();positions.clear();deals.clear();orders.clear();live_orders.clear();logs.clear();g_exit_reports.clear();
 disappear_on_recheck=false;change_on_recheck=false;ResetExcursions();
 orders[100]=Order{.03,0,200};
 Deal entry{1,100,200,DEAL_ENTRY_IN,.03,0};entry.msc=first_stamp;deals.push_back(entry);
 positions.push_back({100,200,.03,0,0});
}
void add_e2() {
 e2_order=101;orders[101]=Order{.03,0,201};
 Deal entry{2,101,201,DEAL_ENTRY_IN,.03,0};entry.msc=1001000;deals.push_back(entry);
 positions.push_back({101,201,.03,0,0});
}
void exit_deal(ulong ticket,ulong order,ulong id,double volume,double pnl,long stamp) {
 Deal d{ticket,order,id,DEAL_ENTRY_OUT,volume,pnl};d.msc=stamp;deals.push_back(d);
}
bool near(double a,double b) { return std::abs(a-b)<1e-9; }
int main() {
 // Always losing, including entry commission. Pending E2 has no floating PnL.
 fresh();positions[0].profit=-5;deals[0].commission=-1;
 e2_order=101;live_orders[101]=Order{.03,.03,0};
 ObserveIdeaExcursions();assert(near(g_excursions.mfe,0) && near(g_excursions.mae,-6));
 assert(g_excursions.e1_msc==first_stamp && g_excursions.mfe_at==1000 && g_excursions.mae_at==1000);
 now=1001;positions[0].profit=-8;ObserveIdeaExcursions();assert(near(g_excursions.mae,-9) && near(g_excursions.mfe,0));
 std::cout<<"PASS: always-losing MFE=0, first actual E1 timestamp, entry costs, pending E2 excluded\n";
 // A positive rebound survives E2 and a negative final result.
 fresh();positions[0].profit=8;now=1001;ObserveIdeaExcursions();assert(near(g_excursions.mfe,8));
 add_e2();positions[0].profit=-7;positions[1].profit=2;ObserveIdeaExcursions();
 assert(near(g_excursions.mfe,8) && near(g_excursions.mae,-5) && g_excursions.e1_msc==first_stamp);
 positions[0].profit=-10;positions[1].profit=9;now=1002;ObserveIdeaExcursions();assert(near(g_excursions.mfe,8));
 positions[0].profit=2;positions[1].profit=9;ObserveIdeaExcursions();assert(near(g_excursions.mfe,11));
 now=1003;ObserveIdeaExcursions();assert(g_excursions.mfe_at==1002); // ties retain first timestamp
 positions.clear();state=CLOSING_IDEA;
 exit_deal(3,102,200,.03,-15,1003000);ObserveIdeaExcursions(); // E2 close still missing
 assert(near(g_excursions.mae,-5));
 QueueExitReport();FlushExitReports();assert(logs.size()==1 && logs[0].tag=="EXIT_PENDING");
 // New idea and changed configuration cannot replace the archived diagnostics.
 configured_budget=100;ResetExcursions();idea_start=2000;state=WAITING_SIGNAL;
 exit_deal(4,103,201,.03,-10,1003579);FlushExitReports();
 assert(logs.size()==2 && logs.back().tag=="EXIT" && near(logs.back().pnl,-25));
 auto text=logs.back().diagnostic;
 for(auto field:{"MFE_USD=11.00","MAE_USD=-25.00","MFE_fecha=1002","MAE_fecha=1003","riesgo_presupuestado_USD=62.50","MFE_R=0.176000","MAE_R=-0.400000","duracion_segundos=3.456"})assert(text.find(field)!=string::npos);
 assert(g_excursions.e1_msc==0 && g_exit_reports.empty()); // no late overwrite of the next idea
 std::cout<<"PASS: E2 preserves joint extremes, no sum of leg maxima, rebound retained, final new MAE, R/budget/duration/timestamps, deferred EXIT identity\n";
 // Partial close: realized costs/swap + current remaining float/swap exactly once.
 fresh();deals[0].commission=-.3;positions[0].volume=.02;positions[0].profit=-2;positions[0].swap=-.4;
 exit_deal(3,102,200,.01,5,1001000);deals[1].commission=-.1;deals[1].swap=-.2;
 now=1001;ObserveIdeaExcursions();assert(near(g_excursions.mfe,2));
 ObserveIdeaExcursions();ObserveIdeaExcursions();assert(near(g_excursions.mfe,2));
 positions[0].volume=.03;positions[0].profit=999;ObserveIdeaExcursions();assert(near(g_excursions.mfe,2));
 positions[0].volume=.02;positions[0].profit=-2;
 auto closed=deals.back();deals.pop_back();ObserveIdeaExcursions();assert(near(g_excursions.mfe,2));deals.push_back(closed);
 positions.clear();exit_deal(4,103,200,.02,-10,1002000);now=1002;ObserveIdeaExcursions();
 assert(near(g_excursions.mae,-5.6)); // 5 -10 -.3 -.1 -.2, no old floating -2 or remaining swap -.4
 std::cout<<"PASS: partial-close commissions/swap, idempotent history rereads, stale floating and missing history not double-counted\n";
 fresh();positions[0].profit=3;ObserveIdeaExcursions();
 positions[0].profit=999;disappear_on_recheck=true;ObserveIdeaExcursions();assert(near(g_excursions.mfe,3));
 fresh();positions[0].profit=3;ObserveIdeaExcursions();positions[0].profit=999;change_on_recheck=true;ObserveIdeaExcursions();assert(near(g_excursions.mfe,3));
 history_available=false;ObserveIdeaExcursions();assert(near(g_excursions.mfe,3));history_available=true;positions[0].profit=4;ObserveIdeaExcursions();assert(near(g_excursions.mfe,4));
 fresh();positions.push_back({900,900,.03,999,0,1,99999});ObserveIdeaExcursions();assert(near(g_excursions.mfe,0));
 fresh();positions.push_back({900,900,.03,999,0});ObserveIdeaExcursions();assert(g_excursions.e1_msc==0); // unknown own identity awaits history
 fresh();netting=true;Deal foreign{77,777,200,DEAL_ENTRY_IN,.01,0};foreign.magic=999;deals.push_back(foreign);ObserveIdeaExcursions();assert(g_excursions.e1_msc==0);
 fresh();netting=true;positions[0].profit=3;ObserveIdeaExcursions();
 positions[0].updated=1006000;positions[0].profit=999;ObserveIdeaExcursions();assert(near(g_excursions.mfe,3));
 // History catches up with two offsetting volume changes on the same position.
 e2_order=101;orders[101]=Order{.01,0,200};Deal offset_entry{2,101,200,DEAL_ENTRY_IN,.01,0};offset_entry.msc=1005000;deals.push_back(offset_entry);
 exit_deal(3,102,200,.01,0,1006000);positions[0].profit=4;now=1006;ObserveIdeaExcursions();assert(near(g_excursions.mfe,4));
 std::cout<<"PASS: portfolio disappearance/version races, incomplete history preserves state, foreign exposure excluded, mixed netting unmeasurable\n";
 // Both exits in the same second, in every enumeration order, update final MAE once.
 std::vector<int> indices={0,1,2,3};
 do {
  fresh();positions[0].profit=10;ObserveIdeaExcursions();add_e2();
  exit_deal(3,102,200,.03,-35.37,1001999);exit_deal(4,103,201,.03,-14.52,1001999);positions.clear();
  auto all=deals;deals.clear();for(int i:indices)deals.push_back(all[i]);
  QueueExitReport();FlushExitReports();assert(logs.size()==1 && near(logs[0].pnl,-49.89));
  assert(logs[0].diagnostic.find("MFE_USD=10.00")!=string::npos && logs[0].diagnostic.find("MAE_USD=-49.89")!=string::npos);
  FlushExitReports();assert(logs.size()==1);
 } while(std::next_permutation(indices.begin(),indices.end()));
 fresh();netting=true;add_e2();deals[1].id=200;orders[101].id=200;positions.resize(1);positions[0].volume=.06;positions[0].profit=12;ObserveIdeaExcursions();assert(near(g_excursions.mfe,12));
 fresh();e1_order=0;positions.clear();deals.clear();orders.clear();had_exposure=false;QueueExitReport();FlushExitReports();assert(logs[0].diagnostic.find("MFE_MAE_disponible=false")!=string::npos);
 std::cout<<"PASS: 24 simultaneous-exit permutations, netting consolidated volume, no E1 execution marked unavailable\n";
}

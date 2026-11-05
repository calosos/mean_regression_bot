// Deterministic regression scenarios; production functions are injected from the current EA.
std::vector<Deal> base={
 {1,100,200,DEAL_ENTRY_IN,.03,0},
 {2,101,201,DEAL_ENTRY_IN,.03,0},
 {3,102,200,DEAL_ENTRY_OUT,.03,-35.37},
 {4,103,201,DEAL_ENTRY_OUT,.03,-14.52}
};
void reset() {
 now=1790566265; idea_start=1790566264; e1_order=100;e2_order=101;had_exposure=true;state=ACTIVE_IDEA;
 netting=false;history_ok=true;history_available=true;entries=0;realized=0;
 position_ids.clear();g_exit_reports.clear();logs.clear();deals.clear();orders.clear();
 orders[100]=Order{.03,0,200};orders[101]=Order{.03,0,201};
}
int main() {
 int permutations=0;
 std::vector<int> indexes={0,1,2,3};
 do {
  reset(); for(int i:indexes) deals.push_back(base[i]);
  // E2 never appeared in live positions: IDs must be learned from entry history.
  InspectIdeaHistory(); assert(Tracked(200) && Tracked(201));
  assert(std::abs(realized+49.89)<1e-9 && entries==2 && state==CLOSING_IDEA);
  QueueExitReport(); FlushExitReports();
  assert(logs.size()==1 && logs[0].tag=="EXIT" && logs[0].idea==1790566264);
  assert(std::abs(logs[0].pnl+49.89)<1e-9 && logs[0].count==2);
  FlushExitReports(); assert(logs.size()==1); permutations++;
 } while(std::next_permutation(indexes.begin(),indexes.end()));
 // Every subset must withhold final EXIT until all entry/exit volume reconciles.
 for(int mask=0;mask<15;mask++) {
  reset(); QueueExitReport();
  for(int i=0;i<4;i++) if(mask & (1<<i)) deals.push_back(base[i]);
  FlushExitReports();FlushExitReports(); assert(logs.size()==1 && logs[0].tag=="EXIT_PENDING");
  assert(g_exit_reports.size()==1);
  // Cooldown finishes and a later idea overwrites all mutable active identity.
  state=WAITING_SIGNAL;now=1790567400;idea_start=1790567400;e1_order=900;e2_order=901;position_ids={999};
  deals=base;FlushExitReports(); assert(logs.size()==2 && logs.back().tag=="EXIT");
  assert(logs.back().idea==1790566264 && logs.back().count==2 && std::abs(logs.back().pnl+49.89)<1e-9);
  assert(state==WAITING_SIGNAL && idea_start==1790567400 && e1_order==900 && position_ids[0]==999);
 }
 std::cout<<"PASS: 24 permutations of E2 and both same-second exits; all 15 incomplete subsets withheld; delayed report keeps original identity after next idea\n";
 reset();QueueExitReport();deals=base;orders.erase(101);FlushExitReports();assert(logs[0].tag=="EXIT_PENDING");
 orders[101]=Order{.03,0,201};FlushExitReports();assert(logs.back().tag=="EXIT");
 reset();QueueExitReport();deals=base;history_available=false;FlushExitReports();assert(logs[0].tag=="EXIT_PENDING");
 history_available=true;FlushExitReports();assert(logs.back().tag=="EXIT");
 reset();netting=true;deals=base;for(auto &d:deals) d.id=200;orders[101].id=200;QueueExitReport();FlushExitReports();
 assert(logs.size()==1 && logs[0].count==2 && std::abs(logs[0].pnl+49.89)<1e-9);
 reset();deals=base;deals[2].pnl=0;deals[3].pnl=0;QueueExitReport();FlushExitReports();assert(logs.size()==1 && logs[0].pnl==0);
 reset();deals=base;deals[0].commission=-1;deals[3].swap=-.2;deals[3].fee=-.1;QueueExitReport();FlushExitReports();
 assert(std::abs(logs[0].pnl+51.19)<1e-9);
 std::cout<<"PASS: missing order history, history unavailable then recovered, netting E2, valid zero PnL, commissions/swap/fees\n";
 reset();QueueExitReport();idea_start=1790567400;position_ids={888};e1_order=900;e2_order=0;QueueExitReport();
 assert(g_exit_reports.size()==2 && g_exit_reports[0].ids.empty() && g_exit_reports[1].ids[0]==888);
 RemoveExitReport(0);assert(g_exit_reports.size()==1 && g_exit_reports[0].idea_id==1790567400 && g_exit_reports[0].ids[0]==888);
 reset();e2_order=0;deals={base[0],base[2]};QueueExitReport();FlushExitReports();assert(logs[0].tag=="EXIT" && logs[0].count==1);
 reset();orders[101]=Order{.03,.03,0,ORDER_STATE_CANCELED};deals={base[0],base[2]};QueueExitReport();FlushExitReports();
 assert(logs[0].tag=="EXIT" && logs[0].count==1);
 reset();orders[101]=Order{.03,.02,201,ORDER_STATE_CANCELED};deals=base;deals[1].volume=.01;deals[3].volume=.01;
 QueueExitReport();FlushExitReports();assert(logs[0].tag=="EXIT" && logs[0].count==2);
 reset();e1_order=0;e2_order=0;position_ids={200};deals={base[0],base[2]};QueueExitReport();FlushExitReports();
 assert(logs[0].tag=="EXIT" && logs[0].count==1);
 // One position closes in several deals: one missing exit must keep the report pending.
 reset();deals=base;deals[3].volume=.01;QueueExitReport();FlushExitReports();assert(logs[0].tag=="EXIT_PENDING");
 deals.push_back({5,104,201,DEAL_ENTRY_OUT,.02,-5});FlushExitReports();assert(logs.back().tag=="EXIT" && logs.back().count==2);
 std::cout<<"PASS: independent queued snapshots, one-entry/cancelled/partially filled E2, restart cleanup, partial exits\n";
}

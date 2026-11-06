void reset_guard(){
 InpStrategy=BB_REENTRY;InpSignalMode=INTRABAR;InpReentryWeekendGuard=true;InpWeekendEntryBlockMinutes=60;InpWeekendCloseMinutes=30;
 g_weekend_valid=g_weekend_blocked=g_weekend_known=g_weekend_close_due=false;
 g_weekend_close=g_weekend_reopen=g_weekend_refresh=g_weekend_observed=g_weekend_missed=0;g_weekend_problem="";
 state=WAITING_SIGNAL;own_positions=own_orders=0;manual_required=false;history_ok=true;foreign=false;
 pending.clear();opens.clear();band_reads.clear();stoch_reads.clear();atr_reads.clear();reentry_state=NONE;reentry_outer_bar=0;
 series_ready=rates_ready=closed_bands_ready=tp_bands_ready=stoch_ready=atr_ready=true;
 event_tags.clear();close_calls=tp_syncs=rejected_logs=0;exit_reason="";g_sl=50;target=200;direction=1;profit=0;tp_bar=0;g_last_signal_bar=SUNDAY;
 candles[0]={SUNDAY,89,111,100};candles[1]={SUNDAY-300,179,221,179};
}
void tick_weekend(datetime stamp){now=stamp;datetime bar=stamp/300*300;candles[0].time=bar;candles[1].time=bar-300;OnTick();}
int main(){
 long end=0,start=0;string problem;
 weekdays();assert(ReadWeeklyBreak(end,start,problem));
 assert(end==5*DAY+23*3600 && start==8*DAY+3600); // Mon reopen, daily gaps 2h ignored
 reset_guard();now=SUNDAY+3*DAY;RefreshWeekendGuard();assert(g_weekend_valid && !g_weekend_blocked);
 // All daily pauses stay unblocked, including their endpoints.
 for(int day=2;day<=4;day++)for(int hour:{0,1,22,23}){reset_guard();now=SUNDAY+day*DAY+hour*3600;RefreshWeekendGuard();assert(!g_weekend_blocked && !g_weekend_close_due);}
 datetime friday=SUNDAY+5*DAY+23*3600;
 reset_guard();now=friday-3601;RefreshWeekendGuard();assert(!g_weekend_blocked);
 reentry_state=WAIT_BUY_REENTRY;reentry_outer_bar=now-300;
 now=friday-3600;RefreshWeekendGuard();assert(g_weekend_blocked && !g_weekend_close_due && reentry_state==NONE);
 now=friday-1801;RefreshWeekendGuard();assert(!g_weekend_close_due);
 state=ACTIVE_IDEA;own_positions=1;now=friday-1800;RefreshWeekendGuard();assert(state==CLOSING_IDEA && exit_reason=="WEEKEND_GUARD");
 for(int i=0;i<20;i++)tick_weekend(friday-1800+i);assert(close_calls==20 && state==CLOSING_IDEA && own_positions==1 && tp_syncs>0);
 now=friday;RefreshWeekendGuard();assert(g_weekend_missed==friday && g_weekend_blocked);
 now=friday+DAY;RefreshWeekendGuard();assert(g_weekend_blocked);
 tick_weekend(SUNDAY+8*DAY+3600);assert(!g_weekend_blocked && state==CLOSING_IDEA && opens.empty() && reentry_state==NONE);
 // First event after reopening cannot process an old/pre-block bar.
 reset_guard();now=friday;RefreshWeekendGuard();tick_weekend(SUNDAY+8*DAY+3600);
 assert(!g_weekend_blocked && opens.empty() && reentry_state==NONE);
 // If no events arrived in the close window, exposure surviving reopening still closes.
 reset_guard();now=friday-7200;RefreshWeekendGuard();state=ACTIVE_IDEA;own_positions=1;
 tick_weekend(SUNDAY+8*DAY+3600);assert(state==CLOSING_IDEA && exit_reason=="WEEKEND_GUARD" && g_weekend_missed==friday);
 // Schedule changes are observed, using server date over the week seam.
 weekdays();reset_guard();now=SUNDAY+2*DAY;RefreshWeekendGuard();datetime previous=g_weekend_close;
 sessions[5][0].end=22*3600;now+=60;RefreshWeekendGuard();assert(g_weekend_close==previous-3600);
 // Multiple unordered/overlapping sessions and 00:00 end.
 weekdays();sessions[5]={{20*3600,0},{3600,12*3600},{11*3600,13*3600}};
 assert(ReadWeeklyBreak(end,start,problem) && end==6*DAY && start==8*DAY+3600);
 // Overnight sessions: Friday's final session ends Saturday at 02:00.
 weekdays();sessions[5]={{22*3600,2*3600}};
 assert(ReadWeeklyBreak(end,start,problem) && end==6*DAY+2*3600 && start==8*DAY+3600);
 // Sunday reopen and wrapped previous-Friday close on Sunday morning.
 fresh_schedule();sessions[0]={{22*3600,0}};for(int day=1;day<=5;day++)sessions[day]={{0,22*3600}};
 assert(ReadWeeklyBreak(end,start,problem) && end==5*DAY+22*3600 && start==WEEK+22*3600);
 reset_guard();now=SUNDAY+12*3600;RefreshWeekendGuard();assert(g_weekend_blocked && g_weekend_close==SUNDAY-2*DAY+22*3600);
 now=SUNDAY+22*3600;RefreshWeekendGuard();assert(!g_weekend_blocked);
 // Full-day trading across weekdays; 00:00-00:00 is a complete day.
 fresh_schedule();for(int day=1;day<=5;day++)sessions[day]={{0,86400}};
 assert(ReadWeeklyBreak(end,start,problem) && end==6*DAY && start==8*DAY);
 for(int day=0;day<7;day++)sessions[day]={{0,86400}};assert(!ReadWeeklyBreak(end,start,problem)); // 24/7: no identifiable break
 fresh_schedule();assert(!ReadWeeklyBreak(end,start,problem));
 weekdays();sessions[3].clear();assert(!ReadWeeklyBreak(end,start,problem)); // two extended gaps ambiguous
 weekdays();sessions[2]={{3600,3600}};assert(!ReadWeeklyBreak(end,start,problem));
 weekdays();session_error=4302;assert(!ReadWeeklyBreak(end,start,problem));
 reset_guard();now=SUNDAY+3*DAY;reentry_state=WAIT_BUY_REENTRY;RefreshWeekendGuard();assert(g_weekend_blocked && !g_weekend_valid && reentry_state==NONE);
 state=ACTIVE_IDEA;own_positions=1;RefreshWeekendGuard();assert(state==ACTIVE_IDEA); // invalid schedule does not force exits
 session_error=0;now+=60;RefreshWeekendGuard();assert(g_weekend_valid && !g_weekend_blocked);
 // Guard disabled and ORIGINAL never consult sessions or interfere with preparation.
 reset_guard();session_reads=0;InpReentryWeekendGuard=false;reentry_state=WAIT_BUY_REENTRY;RefreshWeekendGuard();assert(session_reads==0 && reentry_state==WAIT_BUY_REENTRY);
 InpStrategy=ORIGINAL;InpReentryWeekendGuard=true;RefreshWeekendGuard();assert(session_reads==0);
 std::cout<<"PASS: weekly sessions/daily gaps, exact boundaries, close retries/supervision, exposure at deadline, reopening, overnight/midnight, schedule changes, missing/ambiguous data and disabled/ORIGINAL isolation\n";

 weekdays();reset_guard();tick_weekend(friday-3600);assert(g_weekend_blocked && reentry_state==NONE && opens.empty());
 size_t events=event_tags.size();
 for(int sec=1;sec<120;sec++)tick_weekend(friday-3600+sec);
 assert(event_tags.size()==events && opens.empty() && reentry_state==NONE); // no per-tick schedule/block logs
 for(int step=1;step<5;step++)tick_weekend(friday-3600+step*300);
 assert(opens.empty() && reentry_state==NONE);
 // New initialization during the weekly break applies the blocking/closing flags immediately.
 reset_guard();state=ACTIVE_IDEA;own_positions=1;now=friday+3600;RefreshWeekendGuard();
 assert(g_weekend_blocked && state==CLOSING_IDEA && exit_reason=="WEEKEND_GUARD");
 // Existing exposure under an invalid timetable still follows normal money-risk management.
 weekdays();session_error=4302;reset_guard();state=ACTIVE_IDEA;own_positions=1;profit=-63;
 tick_weekend(SUNDAY+3*DAY);assert(state==CLOSING_IDEA && exit_reason=="Limite monetario flotante" && close_calls==1);
 // Mixed/manual-required ownership is handled by the existing protected cleanup route.
 weekdays();reset_guard();state=ACTIVE_IDEA;manual_required=true;own_positions=1;
 tick_weekend(friday-1800);assert(opens.empty() && close_calls==1 && tp_syncs==0);
 std::cout<<"PASS: blocked opportunities never accumulate preparation, logs are transition-only, initial close window, invalid-schedule money supervision and manual ownership route\n";

 g_weekend_valid=g_weekend_blocked=g_weekend_known=g_weekend_close_due=true;
 g_weekend_refresh=now+999;g_weekend_close=123;g_weekend_problem="old";
 ResetWeekendGuard();assert(!g_weekend_valid && !g_weekend_blocked && !g_weekend_known && !g_weekend_close_due && g_weekend_refresh==0 && g_weekend_close==0 && g_weekend_problem.empty());
 std::cout<<"PASS: initialization resets all weekly cache/state before recomputing current window\n";

 weekdays();reset_guard();InpStrategy=BB_WICK_REJECTION;now=friday-3600;RefreshWeekendGuard();assert(g_weekend_blocked);
 state=ACTIVE_IDEA;own_positions=1;now=friday-1800;RefreshWeekendGuard();assert(state==CLOSING_IDEA && exit_reason=="WEEKEND_GUARD");
 std::cout<<"PASS: V6 weekly block/close shares existing guard\n";

 weekdays();reset_guard();InpStrategy=ATR_DEVIATION_REENTRY;reentry_state=WAIT_BUY_REENTRY;now=friday-3600;
 RefreshWeekendGuard();assert(g_weekend_blocked && reentry_state==NONE);
 state=ACTIVE_IDEA;own_positions=1;now=friday-1800;RefreshWeekendGuard();assert(state==CLOSING_IDEA && exit_reason=="WEEKEND_GUARD");
 std::cout<<"PASS: ATR deviation weekly block clears preparation and initiates common close\n";

 weekdays();reset_guard();InpStrategy=BB_REENTRY;InpReentryExitMode=EXIT_ATR_FIXED_2;state=ACTIVE_IDEA;own_positions=1;target=130;g_sl=50;
 band_reads.clear();now=friday-1800;RefreshWeekendGuard();assert(state==CLOSING_IDEA && exit_reason=="WEEKEND_GUARD");
 SuperviseWeekendClose();assert(target==130 && g_sl==50 && band_reads.empty());
 std::cout<<"PASS: S3 weekly exit stays active and its closing supervision never recalculates fixed target\n";
}

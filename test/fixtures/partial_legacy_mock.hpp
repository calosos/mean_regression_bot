// Inert collaborators for old-mode regression scenarios. New partial tests use
// HALF_REAL and inject the production functions instead.
struct HalfExitState {
 bool triggered=false,pending=false,trailing=false;
 double initial_volume=0,close_volume=0,extreme=0,requested_sl=0;
 ulong position_id=0,ticket=0,order=0;
 uint request_id=0,sequence=0;
 std::string comment;
};
HalfExitState g_half;
#ifndef HALF_REAL
#ifndef HALF_ROUTE
bool HalfExitMode(){return false;}
#else
int partial_step_calls=0;
bool HalfExitMode(){return InpStrategy==BB_REENTRY && InpReentryExitMode==EXIT_HALF_SMA20_TRAIL_ATR;}
#endif
void ResetHalfExit(){g_half=HalfExitState{};}
void ObserveHalfExtreme(){}
void HalfExitStep(){
#ifdef HALF_ROUTE
 partial_step_calls++;
#endif
}
bool ReconcileHalfExit(double &closed){closed=0;return true;}
bool IgnoreHalfDeal(ulong){return false;}
#endif

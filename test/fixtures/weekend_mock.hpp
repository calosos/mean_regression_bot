#define WEEKEND_REAL
#include "signal_modes_mock.hpp"
#include <ctime>
#include <algorithm>
using ENUM_DAY_OF_WEEK=int;
const int ERR_MARKET_SESSION_INDEX=4307;
struct MqlDateTime{int year=1970,mon=1,day=1,hour=0,min=0,sec=0,day_of_week=0;};
bool TimeToStruct(datetime stamp,MqlDateTime &out){time_t raw=stamp;std::tm value={};if(!gmtime_r(&raw,&value))return false;out.hour=value.tm_hour;out.min=value.tm_min;out.sec=value.tm_sec;out.day_of_week=value.tm_wday;return true;}
struct RawSession{datetime begin,end;};std::vector<RawSession> sessions[7];
int session_error=0,last_error=0,session_reads=0;
void ResetLastError(){last_error=0;}int GetLastError(){return last_error;}
bool SymbolInfoSessionTrade(const string&,int day,uint index,datetime &from,datetime &to){
 session_reads++;if(session_error){last_error=session_error;return false;}
 if(index>=sessions[day].size()){last_error=ERR_MARKET_SESSION_INDEX;return false;}
 from=sessions[day][index].begin;to=sessions[day][index].end;return true;
}
// The adapter uses a known Sunday in synthetic server time (1970-01-04).
const datetime SUNDAY=259200,DAY=86400,WEEK=604800;
void fresh_schedule(){for(auto &day:sessions)day.clear();session_error=last_error=session_reads=0;}
void weekdays(){fresh_schedule();for(int d=1;d<=5;d++)sessions[d].push_back({3600,23*3600});}
void reset_guard();

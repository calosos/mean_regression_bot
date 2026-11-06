// Test-only MT5 adapters. No trading server or account connection.
#include <string>
#include <vector>
#include <cstdio>
#include <ctime>
#include <cassert>
#include <iostream>
using string=std::string;using datetime=long long;
const int PERIOD_M5=5,TIME_DATE=1,TIME_SECONDS=2;
enum SignalMode{INTRABAR,CLOSED_BAR};SignalMode InpSignalMode=CLOSED_BAR;
struct MqlRates{datetime time;double open,high,low,close;};
struct MqlTick{datetime time;double bid,ask;};
string _Symbol="XAUUSD";
datetime now=0;bool quote_ok=true,detailed=true;int quote_reads=0;
std::vector<string> logs;
datetime TimeCurrent(){return now;}
int PeriodSeconds(int period){return period*60;}
string TimeToString(datetime value,int){time_t stamp=value;std::tm tm={};gmtime_r(&stamp,&tm);char s[32];std::strftime(s,sizeof(s),"%Y.%m.%d %H:%M:%S",&tm);return s;}
datetime parse(const char *text){std::tm tm={};strptime(text,"%Y.%m.%d %H:%M:%S",&tm);return timegm(&tm);}
bool SymbolInfoTick(const string&,MqlTick &q){quote_reads++;q={now,500,501};return quote_ok;}
const char *arg(const string &value){return value.c_str();}
template<class T> T arg(T value){return value;}
template<class... T> string StringFormat(const char *raw,T... values){string fmt=raw;size_t n;while((n=fmt.find("%I64d"))!=string::npos)fmt.replace(n,5,"%ld");int size=std::snprintf(nullptr,0,fmt.c_str(),arg(values)...);assert(size>=0);std::vector<char> out(size+1);std::snprintf(out.data(),out.size(),fmt.c_str(),arg(values)...);return out.data();}
void Log(const string &tag,const string &message){if(detailed)logs.push_back(tag+" "+message);}

enum Oscillator { STOCHASTIC, RSI };
Oscillator InpOscillator=STOCHASTIC;
double InpRSIBuyLevel=30,InpRSISellLevel=70;

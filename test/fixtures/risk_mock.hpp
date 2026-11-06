// Test-only MT5 adapters. No trading server or account connection.
#include <cmath>
#include <cassert>
#include <iostream>
#include <algorithm>
#include <vector>
#include <string>
using datetime=long long;
using ENUM_ORDER_TYPE=int;
const int ORDER_TYPE_BUY=0,ORDER_TYPE_SELL=1;
std::string _Symbol="XAUUSD";
int _Digits=2,direction=1;
double tick_size=.01,volume_min=.01,volume_max=100,volume_step=.01;
double frozen_atr=2,InpRiskBaseUSD=25000,InpRiskPercent=.25,InpTPFactor=.9,InpATRMax=8,target=0;
datetime processed_buy=0,processed_sell=0,cooldown_until=0;
enum Strategy { ORIGINAL, BB_REENTRY, BB_WICK_REJECTION, ATR_DEVIATION_REENTRY };
Strategy InpStrategy=ORIGINAL;
enum EAState { WAITING_SIGNAL, ACTIVE_IDEA, CLOSING_IDEA, COOLDOWN };
EAState state=WAITING_SIGNAL;
struct MqlTick { double bid,ask; };
bool fail_profit=false;
double NormalizeDouble(double v,int n) { double scale=std::pow(10,n); return std::round(v*scale)/scale; }
double MathRound(double v) { return std::round(v); }
double MathAbs(double v) { return std::abs(v); }
double MathFloor(double v) { return std::floor(v); }
double MathMin(double a,double b) { return std::min(a,b); }
bool MathIsValidNumber(double v) { return std::isfinite(v); }
bool OrderCalcProfit(int type,const std::string&,double v,double open,double close,double &out) {
 if(fail_profit) return false;
 out=(type==ORDER_TYPE_BUY ? close-open : open-close)*100*v; return true;
}

enum Oscillator { STOCHASTIC, RSI };
Oscillator InpOscillator=STOCHASTIC;
double InpRSIBuyLevel=30,InpRSISellLevel=70;

// Indicator transport failures and invalid values must leave the output untouched.
const double EMPTY_VALUE=1.7976931348623157e308;
int copied=1;
double indicator_value=29;
int CopyBuffer(int,int,int,int,double (&out)[1]){out[0]=indicator_value;return copied;}

void ClearReentry(const std::string&){}

double InpReentrySLATR=3.0;

double InpATRDeviationThreshold=1.5;

enum ReentryExitMode { EXIT_SMA20_DYNAMIC, EXIT_ATR_FIXED_2, EXIT_HALF_SMA20_DYNAMIC, EXIT_OPPOSITE_BAND_DYNAMIC };
ReentryExitMode InpReentryExitMode=EXIT_SMA20_DYNAMIC;
double entry_price=0;

bool HalfExitMode(){return false;}void ResetHalfExit(){}

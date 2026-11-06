#define HALF_ROUTE
#define USE_REAL_TARGET
#include "signal_modes_mock.hpp"
double entry_price=0,InpTPFactor=.9;
double Price(double p){return std::round(p*100)/100;}

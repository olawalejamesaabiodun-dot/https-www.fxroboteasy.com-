//+------------------------------------------------------------------+
//|                                 Volatility_Signal_Dashboard.mq5  |
//|        Multi-symbol Direction & Strength buy/sell signal alerts  |
//|                                                                  |
//| Dashboard covering: Volatility 10, 25, 50, 75, 10(1s), 75(1s),   |
//| 150(1s), 250(1s) Index plus XAUUSD and BTCUSD.                   |
//+------------------------------------------------------------------+
#property copyright "Signal Dashboard"
#property version   "1.00"
#property description "Multi-symbol Direction & Strength dashboard with BUY/SELL signal alerts"
#property description "Default coverage: Volatility 10/25/50/75, 10(1s)/75(1s)/150(1s)/250(1s), XAUUSD, BTCUSD"
#property description "Signals: EMA trend, price vs EMA, RSI, MACD, ADX/DMI confluence (5 votes)"
#property description "Alerts: chart popup, push notification, email, sound. Panel click = minimize."

//--- signal direction values
#define DIR_NONE  0
#define DIR_BUY   1
#define DIR_SELL  (-1)

//--- inputs ------------------------------------------------------------------
input group "════ Symbols ════"
input string InpSymbolsCSV       = "V10,V25,V50,V75,V10s,V75s,V150s,V250s,XAUUSD,BTCUSD"; // Symbols (aliases: V10s = Volatility 10 (1s))
input ENUM_TIMEFRAMES InpTF      = PERIOD_M1;          // Signal timeframe

input group "════ Signal settings ════"
input int    InpEmaFast          = 8;                  // EMA fast period
input int    InpEmaSlow          = 21;                 // EMA slow period
input int    InpRsiPeriod        = 14;                 // RSI period
input double InpRSIBuyLevel      = 55.0;               // RSI bullish level
input double InpRSISellLevel     = 45.0;               // RSI bearish level
input int    InpMacdFast         = 12;                 // MACD fast EMA
input int    InpMacdSlow         = 26;                 // MACD slow EMA
input int    InpMacdSignal       = 9;                  // MACD signal period
input int    InpAdxPeriod        = 14;                 // ADX period
input double InpMinADX           = 20.0;               // Minimum ADX for a valid signal (0 = off)
input int    InpSignalThreshold  = 3;                  // Min vote difference (of 5) for BUY/SELL
input bool   InpUseClosedBar     = true;               // Evaluate on closed bar (non-repainting)

input group "════ Alerts ════"
input bool   InpAlertPopup       = true;               // Chart popup alert
input bool   InpAlertPush        = true;               // Push notification (needs MetaQuotes ID)
input bool   InpAlertEmail       = false;              // Email alert (needs terminal email setup)
input bool   InpAlertSound       = true;               // Sound alert
input string InpSoundFile        = "alert.wav";        // Sound file
input int    InpAlertCooldownMin = 30;                 // Cooldown per symbol (minutes)

input group "════ Dashboard panel ════"
input bool   InpShowPanel        = true;               // Show dashboard panel
input int    InpRefreshSec       = 1;                  // Refresh interval (seconds)
input ENUM_BASE_CORNER InpCorner = CORNER_LEFT_UPPER;  // Panel corner
input int    InpPanelX           = 12;                 // Panel X offset
input int    InpPanelY           = 24;                 // Panel Y offset
input int    InpFontSize         = 10;                 // Font size
input color  InpColBg            = C'18,22,30';        // Panel background
input color  InpColBorder        = C'70,80,100';       // Panel border
input color  InpColTitle         = clrWhite;           // Title color
input color  InpColHeader        = clrDarkGray;        // Column header color
input color  InpColBuy           = clrLime;            // BUY color
input color  InpColSell          = clrTomato;          // SELL color
input color  InpColWait          = clrSilver;          // Neutral color

//--- per-symbol state --------------------------------------------------------
struct SymbolState
  {
   string            name;        // resolved broker symbol
   string            display;     // short display name
   int               hEmaFast;
   int               hEmaSlow;
   int               hRsi;
   int               hMacd;
   int               hAdx;
   double            bid;
   double            adx;
   int               dir;         // +1 buy / -1 sell / 0 neutral
   int               strength;    // 0..100
   int               prevDir;     // previously alerted/evaluated direction
   datetime          lastAlert;
   bool              ready;
  };

SymbolState g_states[];
int         g_count      = 0;
bool        g_minimized  = false;
const string PREF        = "VSD_";

//+------------------------------------------------------------------+
//| Expand short aliases to broker symbols                           |
//+------------------------------------------------------------------+
string AliasToSymbol(string token)
  {
   string t = token;
   StringTrimLeft(t);
   StringTrimRight(t);
   if(t == "")
      return "";
   string u = t;
   StringToUpper(u);
   if(u == "V10")   return "Volatility 10 Index";
   if(u == "V25")   return "Volatility 25 Index";
   if(u == "V50")   return "Volatility 50 Index";
   if(u == "V75")   return "Volatility 75 Index";
   if(u == "V100")  return "Volatility 100 Index";
   if(u == "V10S")  return "Volatility 10 (1s) Index";
   if(u == "V25S")  return "Volatility 25 (1s) Index";
   if(u == "V50S")  return "Volatility 50 (1s) Index";
   if(u == "V75S")  return "Volatility 75 (1s) Index";
   if(u == "V100S") return "Volatility 100 (1s) Index";
   if(u == "V150S") return "Volatility 150 (1s) Index";
   if(u == "V250S") return "Volatility 250 (1s) Index";
   return t;
  }

//+------------------------------------------------------------------+
//| Resolve broker symbol: exact, then case-insensitive, then part.  |
//+------------------------------------------------------------------+
string ResolveSymbol(string token)
  {
   string want = AliasToSymbol(token);
   if(want == "")
      return "";
   if(SymbolSelect(want, true))
      return want;

   int    total = SymbolsTotal(false);
   string wantU = want;
   StringToUpper(wantU);

   for(int i = 0; i < total; i++)
     {
      string s = SymbolName(i, false);
      string su = s;
      StringToUpper(su);
      if(su == wantU && SymbolSelect(s, true))
         return s;
     }
   for(int i = 0; i < total; i++)
     {
      string s = SymbolName(i, false);
      string su = s;
      StringToUpper(su);
      if(StringFind(su, wantU) >= 0 && SymbolSelect(s, true))
         return s;
     }
   return "";
  }

//+------------------------------------------------------------------+
//| Short display name: "Volatility 75 (1s) Index" -> "V75 (1s)"     |
//+------------------------------------------------------------------+
string ShortName(string brokerName)
  {
   string s = brokerName;
   StringReplace(s, "Volatility ", "V");
   StringReplace(s, " Index", "");
   StringReplace(s, " (1s)", "(1s)");
   return s;
  }

//+------------------------------------------------------------------+
//| Timeframe as short string: PERIOD_M1 -> "M1"                     |
//+------------------------------------------------------------------+
string TFToString(ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   StringReplace(s, "PERIOD_", "");
   return s;
  }

//+------------------------------------------------------------------+
//| Parse symbol CSV list and initialize state + indicator handles   |
//+------------------------------------------------------------------+
void ParseSymbolsInput()
  {
   g_count = 0;
   ArrayResize(g_states, 0);

   string parts[];
   int n = StringSplit(InpSymbolsCSV, ',', parts);
   for(int p = 0; p < n; p++)
     {
      string resolved = ResolveSymbol(parts[p]);
      if(resolved == "")
        {
         PrintFormat("Dashboard: symbol '%s' not found on this broker - skipped", parts[p]);
         continue;
        }

      bool dup = false;
      for(int k = 0; k < g_count; k++)
         if(g_states[k].name == resolved) { dup = true; break; }
      if(dup)
         continue;

      int hEmaFast = iMA(resolved, InpTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
      int hEmaSlow = iMA(resolved, InpTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
      int hRsi     = iRSI(resolved, InpTF, InpRsiPeriod, PRICE_CLOSE);
      int hMacd    = iMACD(resolved, InpTF, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);
      int hAdx     = iADX(resolved, InpTF, InpAdxPeriod);

      if(hEmaFast == INVALID_HANDLE || hEmaSlow == INVALID_HANDLE ||
         hRsi == INVALID_HANDLE || hMacd == INVALID_HANDLE || hAdx == INVALID_HANDLE)
        {
         PrintFormat("Dashboard: failed to create indicators for '%s' - skipped", resolved);
         if(hEmaFast != INVALID_HANDLE) IndicatorRelease(hEmaFast);
         if(hEmaSlow != INVALID_HANDLE) IndicatorRelease(hEmaSlow);
         if(hRsi     != INVALID_HANDLE) IndicatorRelease(hRsi);
         if(hMacd    != INVALID_HANDLE) IndicatorRelease(hMacd);
         if(hAdx     != INVALID_HANDLE) IndicatorRelease(hAdx);
         continue;
        }

      int i = g_count;
      ArrayResize(g_states, g_count + 1);
      g_states[i].name      = resolved;
      g_states[i].display   = ShortName(resolved);
      g_states[i].hEmaFast  = hEmaFast;
      g_states[i].hEmaSlow  = hEmaSlow;
      g_states[i].hRsi      = hRsi;
      g_states[i].hMacd     = hMacd;
      g_states[i].hAdx      = hAdx;
      g_states[i].bid       = 0.0;
      g_states[i].adx       = 0.0;
      g_states[i].dir       = DIR_NONE;
      g_states[i].strength  = 0;
      g_states[i].prevDir   = DIR_NONE;
      g_states[i].lastAlert = 0;
      g_states[i].ready     = false;
      g_count++;
     }
  }

//+------------------------------------------------------------------+
//| Copy one indicator buffer safely                                 |
//+------------------------------------------------------------------+
int GetBuffer(int handle, int buffer, int start, int count, double &out[])
  {
   if(handle == INVALID_HANDLE)
      return 0;
   ArraySetAsSeries(out, true);
   return CopyBuffer(handle, buffer, start, count, out);
  }

//+------------------------------------------------------------------+
//| Strength gauge bar (10 cells)                                    |
//+------------------------------------------------------------------+
string StrengthBar(int strength)
  {
   int filled = (int)MathRound(strength / 10.0);
   string s = "";
   for(int i = 0; i < 10; i++)
      s += (i < filled) ? "█" : "░";
   return s;
  }

//+------------------------------------------------------------------+
//| Recompute direction & strength for one symbol                    |
//+------------------------------------------------------------------+
void UpdateSymbol(SymbolState &st)
  {
   st.ready = false;
   if(!SymbolSelect(st.name, true))
      return;
   st.bid = SymbolInfoDouble(st.name, SYMBOL_BID);
   if(st.bid <= 0.0)
      return;

   int shift = InpUseClosedBar ? 1 : 0;

   double emaF[], emaS[], rsi[], macdM[], macdS[], adxM[], diP[], diM[], close[];
   if(GetBuffer(st.hEmaFast, 0, shift, 1, emaF)  != 1) return;
   if(GetBuffer(st.hEmaSlow, 0, shift, 1, emaS)  != 1) return;
   if(GetBuffer(st.hRsi,     0, shift, 1, rsi)   != 1) return;
   if(GetBuffer(st.hMacd,    0, shift, 1, macdM) != 1) return;
   if(GetBuffer(st.hMacd,    1, shift, 1, macdS) != 1) return;
   if(GetBuffer(st.hAdx,     0, shift, 1, adxM)  != 1) return;
   if(GetBuffer(st.hAdx,     1, shift, 1, diP)   != 1) return;
   if(GetBuffer(st.hAdx,     2, shift, 1, diM)   != 1) return;

   double px = st.bid;
   if(InpUseClosedBar)
     {
      if(CopyClose(st.name, InpTF, shift, 1, close) != 1)
         return;
      px = close[0];
     }

   int bull = 0, bear = 0;
   if(emaF[0] > emaS[0]) bull++; else if(emaF[0] < emaS[0]) bear++;   // EMA trend
   if(px > emaF[0])      bull++; else if(px < emaF[0])      bear++;   // price vs fast EMA
   if(rsi[0] >= InpRSIBuyLevel)   bull++;                              // RSI momentum
   else if(rsi[0] <= InpRSISellLevel) bear++;
   if(macdM[0] > macdS[0]) bull++; else if(macdM[0] < macdS[0]) bear++; // MACD momentum
   if(diP[0] > diM[0])   bull++; else if(diP[0] < diM[0])   bear++;     // ADX/DMI

   st.adx = adxM[0];

   int net = bull - bear;
   int dir = DIR_NONE;
   if(net >= InpSignalThreshold)
      dir = DIR_BUY;
   else if(net <= -InpSignalThreshold)
      dir = DIR_SELL;
   if(dir != DIR_NONE && InpMinADX > 0.0 && adxM[0] < InpMinADX)
      dir = DIR_NONE;

   st.dir      = dir;
   st.ready    = true;
   if(dir == DIR_BUY)
      st.strength = (int)MathRound(100.0 * bull / 5.0);
   else if(dir == DIR_SELL)
      st.strength = (int)MathRound(100.0 * bear / 5.0);
   else
      st.strength = (int)MathRound(100.0 * MathMax(bull, bear) / 5.0);
  }

//+------------------------------------------------------------------+
//| Fire signal alerts                                               |
//+------------------------------------------------------------------+
void CheckAlert(SymbolState &st)
  {
   if(st.dir == st.prevDir)
      return;
   if(st.dir != DIR_NONE && st.ready &&
      (TimeCurrent() - st.lastAlert) >= (long)InpAlertCooldownMin * 60)
     {
      int    digits = (int)SymbolInfoInteger(st.name, SYMBOL_DIGITS);
      string type   = (st.dir == DIR_BUY) ? "BUY" : "SELL";
      string msg    = StringFormat("%s SIGNAL | %s | Strength %d%% | ADX %.1f | %s | Price %s",
                                   type, st.name, st.strength, st.adx,
                                   TFToString(InpTF),
                                   DoubleToString(st.bid, digits));
      Print(msg);

      if(InpAlertPopup)
         Alert(msg);
      if(InpAlertPush)
        {
         if(!SendNotification(msg))
            Print("Dashboard: push notification failed (check MetaQuotes ID in terminal settings)");
        }
      if(InpAlertEmail)
         SendMail("MT5 Signal Dashboard", msg);
      if(InpAlertSound)
         PlaySound(InpSoundFile);

      st.lastAlert = TimeCurrent();
     }
   st.prevDir = st.dir;
  }

//+------------------------------------------------------------------+
//| Panel helpers                                                    |
//+------------------------------------------------------------------+
void CreateRect(string name, int x, int y, int w, int h, color bg, color border)
  {
   string on = PREF + name;
   if(ObjectFind(0, on) < 0)
      ObjectCreate(0, on, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, on, OBJPROP_CORNER, InpCorner);
   ObjectSetInteger(0, on, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, on, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, on, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, on, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, on, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, on, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, on, OBJPROP_COLOR, border);
   ObjectSetInteger(0, on, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, on, OBJPROP_BACK, false);
   ObjectSetInteger(0, on, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, on, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, on, OBJPROP_ZORDER, 5);
  }

void CreateText(string name, int x, int y, string text, color clr, int fs)
  {
   string on = PREF + name;
   if(ObjectFind(0, on) < 0)
      ObjectCreate(0, on, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, on, OBJPROP_CORNER, InpCorner);
   ObjectSetInteger(0, on, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, on, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, on, OBJPROP_TEXT, text);
   ObjectSetString(0, on, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, on, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, on, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, on, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, on, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, on, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, on, OBJPROP_ZORDER, 10);
  }

void SetText(string name, string text, color clr)
  {
   string on = PREF + name;
   ObjectSetString(0, on, OBJPROP_TEXT, text);
   ObjectSetInteger(0, on, OBJPROP_COLOR, clr);
  }

void ShowObject(string name, bool show)
  {
   string on = PREF + name;
   ObjectSetInteger(0, on, OBJPROP_TIMEFRAMES, show ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
  }

//+------------------------------------------------------------------+
//| Build the static panel structure                                 |
//+------------------------------------------------------------------+
void CreateDashboard()
  {
   if(!InpShowPanel)
      return;

   int rows   = g_count > 0 ? g_count : 1;
   int width  = 480;
   int height = 78 + rows * (InpFontSize + 11) + 14;

   CreateRect("bg", InpPanelX, InpPanelY, width, height, InpColBg, InpColBorder);
   CreateText("title", InpPanelX + 12, InpPanelY + 8,
              "SIGNAL DASHBOARD — DIRECTION & STRENGTH", InpColTitle, InpFontSize);
   CreateText("info", InpPanelX + 12, InpPanelY + 8 + InpFontSize + 9,
              TFToString(InpTF) + "  |  loading...", InpColHeader, InpFontSize - 1);
   CreateText("header", InpPanelX + 12, InpPanelY + 8 + 2 * (InpFontSize + 10),
              "SYMBOL        SIGNAL   STRENGTH       ADX  PRICE", InpColHeader, InpFontSize - 1);

   for(int i = 0; i < g_count; i++)
     {
      int y = InpPanelY + 78 + i * (InpFontSize + 11);
      CreateText("row" + (string)i, InpPanelX + 12, y, "...", InpColWait, InpFontSize);
     }
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Refresh dynamic panel content                                    |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowPanel || g_count == 0)
      return;

   int buys = 0, sells = 0;
   for(int i = 0; i < g_count; i++)
     {
      if(g_states[i].ready && g_states[i].dir == DIR_BUY)  buys++;
      if(g_states[i].ready && g_states[i].dir == DIR_SELL) sells++;
     }

   SetText("info", StringFormat("%s  |  BUY %d  SELL %d  WAIT %d  |  updated %s",
           TFToString(InpTF), buys, sells, g_count - buys - sells,
           TimeToString(TimeCurrent(), TIME_MINUTES | TIME_SECONDS)),
           InpColHeader);

   ShowObject("bg", !g_minimized);
   ShowObject("info", !g_minimized);
   ShowObject("header", !g_minimized);

   for(int i = 0; i < g_count; i++)
     {
      ShowObject("row" + (string)i, !g_minimized);
      if(g_minimized)
         continue;

      int     digits = (int)SymbolInfoInteger(g_states[i].name, SYMBOL_DIGITS);
      string  line, dirText, bar;
      color   clr = InpColWait;

      if(!g_states[i].ready)
        {
         line = StringFormat("%-13s %s", g_states[i].display, "loading...");
        }
      else
        {
         if(g_states[i].dir == DIR_BUY)  { dirText = "BUY";  bar = StrengthBar(g_states[i].strength); clr = InpColBuy; }
         else if(g_states[i].dir == DIR_SELL) { dirText = "SELL"; bar = StrengthBar(g_states[i].strength); clr = InpColSell; }
         else                            { dirText = "WAIT"; bar = StrengthBar(g_states[i].strength); clr = InpColWait; }

         line = StringFormat("%-13s %-6s %s %3d%% %5.1f  %s",
                             g_states[i].display, dirText, bar,
                             g_states[i].strength, g_states[i].adx,
                             DoubleToString(g_states[i].bid, digits));
        }
      SetText("row" + (string)i, line, clr);
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Delete all panel objects                                         |
//+------------------------------------------------------------------+
void DestroyDashboard()
  {
   ObjectsDeleteAll(0, PREF);
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   ParseSymbolsInput();
   if(g_count == 0)
     {
      Print("Dashboard: no valid symbols resolved - check monitoring in Market Watch");
      return INIT_PARAMETERS_INCORRECT;
     }

   CreateDashboard();
   EventSetTimer(MathMax(1, InpRefreshSec));
   UpdateAll();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < g_count; i++)
     {
      if(g_states[i].hEmaFast != INVALID_HANDLE) IndicatorRelease(g_states[i].hEmaFast);
      if(g_states[i].hEmaSlow != INVALID_HANDLE) IndicatorRelease(g_states[i].hEmaSlow);
      if(g_states[i].hRsi     != INVALID_HANDLE) IndicatorRelease(g_states[i].hRsi);
      if(g_states[i].hMacd    != INVALID_HANDLE) IndicatorRelease(g_states[i].hMacd);
      if(g_states[i].hAdx     != INVALID_HANDLE) IndicatorRelease(g_states[i].hAdx);
     }
   DestroyDashboard();
  }

//+------------------------------------------------------------------+
//| Timer: full refresh                                              |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateAll();
  }

//+------------------------------------------------------------------+
//| Refresh all symbols, alerts and the panel                        |
//+------------------------------------------------------------------+
void UpdateAll()
  {
   for(int i = 0; i < g_count; i++)
     {
      UpdateSymbol(g_states[i]);
      CheckAlert(g_states[i]);
     }
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Click on title = minimize/expand the panel                       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, PREF + "title") == 0)
     {
      g_minimized = !g_minimized;
      UpdateDashboard();
     }
  }

//+------------------------------------------------------------------+
//| Ticks only refresh the panel (timer drives signal logic)         |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateDashboard();
  }
//+------------------------------------------------------------------+

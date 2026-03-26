//+------------------------------------------------------------------+
//| Tick_TFEX.mq5                                                    |
//| Tick Collector — S50IF_CON + S50 Futures + S50 Options           |
//| v1: CopyTicksRange poll 10ms + auto-discover futures/options     |
//| Output: tick_tfex.csv                                            |
//+------------------------------------------------------------------+
#property copyright "Quant"
#property version   "1.00"
#property strict
#property description "Tick Collector — TFEX (S50IF_CON + Futures + Options) | poll 10ms"

//── Config ─────────────────────────────────────────────────────────
#define TICK_FILE       "tick_tfex.csv"
#define POLL_MS         10     // poll ticks ทุก 10ms
#define HEARTBEAT_SEC   30
#define RESYNC_SEC      300    // re-discover ทุก 5 นาที

//── Core symbol ─────────────────────────────────────────────────────
#define MAIN_SYM        "S50IF_CON"

//── Globals ─────────────────────────────────────────────────────────
int      g_fh            = INVALID_HANDLE;
long     g_ticks         = 0;
datetime g_last_hb       = 0;
datetime g_last_discover = 0;

//── Symbol tracking ─────────────────────────────────────────────────
string   g_syms[];        // all tracked symbols (CON + futures + options)
ulong    g_last_ms[];     // last tick time_msc per symbol
int      g_sym_count     = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!OpenFile()) return INIT_FAILED;

   // Always track S50IF_CON first
   SymbolSelect(MAIN_SYM, true);
   AddSymbol(MAIN_SYM);

   // Discover futures & options
   DiscoverTFEX();
   g_last_hb       = TimeCurrent();
   g_last_discover = TimeCurrent();

   EventSetMillisecondTimer(POLL_MS);
   Print("[TICK_TFEX] Started | ", g_sym_count, " symbols | poll=", POLL_MS, "ms | file=", TICK_FILE);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_fh != INVALID_HANDLE)
     { FileFlush(g_fh); FileClose(g_fh); g_fh = INVALID_HANDLE; }
   Print("[TICK_TFEX] Stopped. ticks=", g_ticks, " | symbols=", g_sym_count);
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   datetime now = TimeCurrent();

   // ─ Poll ticks for all tracked symbols ─
   for(int i = 0; i < g_sym_count; i++)
     {
      MqlTick ticks[];
      // COPY_TICKS_TRADE = เฉพาะ tick ที่มี last price (deal จริง)
      int n = CopyTicksRange(g_syms[i], ticks, COPY_TICKS_TRADE,
                             g_last_ms[i], 0);
      if(n <= 0) continue;

      for(int k = 0; k < n; k++)
        {
         if(ticks[k].last == 0.0) continue;
         WriteTick(g_syms[i], ticks[k]);
        }
      g_last_ms[i] = ticks[n-1].time_msc + 1;
     }

   // ─ Flush ─
   if(g_fh != INVALID_HANDLE) FileFlush(g_fh);

   // ─ Heartbeat ─
   if(now - g_last_hb >= HEARTBEAT_SEC)
     {
      if(g_fh != INVALID_HANDLE)
         FileWrite(g_fh, FormatMs(GetTickCount64()), "TFEX", "HEARTBEAT", "", "", "", "", "");
      g_last_hb = now;
     }

   // ─ Re-discover ทุก 5 นาที ─
   if(now - g_last_discover >= RESYNC_SEC)
     { DiscoverTFEX(); g_last_discover = now; }
  }

void OnTick() { }  // EA อาจ attach บน chart อื่น → ไม่ใช้ OnTick

//+------------------------------------------------------------------+
void DiscoverTFEX()
  {
   int total = SymbolsTotal(false), added = 0;
   for(int i = 0; i < total; i++)
     {
      string name = SymbolName(i, false);
      if(IsTracked(name)) continue;
      if(IsS50Future(name) || IsS50Option(name))
        { SymbolSelect(name, true); AddSymbol(name); added++; }
     }
   if(added > 0)
      Print("[TICK_TFEX] +", added, " symbols. Total=", g_sym_count);
  }

void AddSymbol(const string &sym)
  {
   ArrayResize(g_syms,    g_sym_count + 1);
   ArrayResize(g_last_ms, g_sym_count + 1);
   g_syms[g_sym_count]    = sym;
   // เริ่มเก็บจาก "ตอนนี้" เพื่อไม่ดึง history เก่า
   g_last_ms[g_sym_count] = (ulong)TimeCurrent() * 1000;
   g_sym_count++;
  }

bool IsTracked(const string &sym)
  { for(int i=0;i<g_sym_count;i++) if(g_syms[i]==sym) return true; return false; }

// S50 Futures: S50M26, S50U26 ฯลฯ (length ≤ 6, ไม่มี C/P)
bool IsS50Future(const string &name)
  {
   if(StringLen(name) < 5 || StringLen(name) > 6) return false;
   if(StringSubstr(name, 0, 3) != "S50")           return false;
   if(name == MAIN_SYM)                            return false;
   string m = StringSubstr(name, 3, 1);
   return (StringFind("FGHJKMNQUVXZ", m) >= 0);
  }

// S50 Options: S50H26C1600 ฯลฯ (starts S50, month code, has C or P)
bool IsS50Option(const string &name)
  {
   if(StringLen(name) < 9)              return false;
   if(StringSubstr(name, 0, 3) != "S50") return false;
   string m = StringSubstr(name, 3, 1);
   if(StringFind("HJKMNQUVXZ", m) < 0)  return false;
   return (StringFind(name, "C", 5) >= 0 || StringFind(name, "P", 5) >= 0);
  }

//+------------------------------------------------------------------+
void WriteTick(const string &sym, const MqlTick &t)
  {
   if(g_fh == INVALID_HANDLE && !OpenFile()) return;
   string side = "";
   if((t.flags & TICK_FLAG_BUY)  != 0) side = "buy";
   if((t.flags & TICK_FLAG_SELL) != 0) side = "sell";
   FileWrite(g_fh,
             FormatMs(t.time_msc),
             sym,
             DoubleToString(t.last,        2),
             IntegerToString(t.volume),
             DoubleToString(t.volume_real, 4),
             side,
             DoubleToString(t.bid, 2),
             DoubleToString(t.ask, 2));
   g_ticks++;
  }

// Format broker tick timestamp (ms precision)
string FormatMs(ulong time_msc)
  {
   datetime sec = (datetime)(time_msc / 1000);
   int      ms  = (int)(time_msc % 1000);
   MqlDateTime dt; TimeToStruct(sec, dt);
   return StringFormat("%04d-%02d-%02d %02d:%02d:%02d.%03d000",
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec, ms);
  }

bool OpenFile()
  {
   if(g_fh != INVALID_HANDLE) { FileClose(g_fh); g_fh = INVALID_HANDLE; }
   g_fh = FileOpen(TICK_FILE, FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
   if(g_fh == INVALID_HANDLE)
     {
      g_fh = FileOpen(TICK_FILE, FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI, ',');
      if(g_fh == INVALID_HANDLE)
        { Print("[TICK_TFEX] ERROR opening file: ", GetLastError()); return false; }
      FileWrite(g_fh, "timestamp_ms","symbol","last","volume","volume_real","side","bid","ask");
      FileFlush(g_fh); return true;
     }
   FileSeek(g_fh, 0, SEEK_END); return true;
  }
//+------------------------------------------------------------------+
